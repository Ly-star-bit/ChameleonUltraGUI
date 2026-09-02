import 'package:chameleonultragui/gui/component/antenna_guide.dart';
import 'package:chameleonultragui/gui/component/card_button.dart';
import 'package:chameleonultragui/gui/component/mifare/classic.dart';
import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/gui/component/mifare/ultralight.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/mifare_ultralight/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

enum MifareClassicState {
  none,
  checkKeys,
  checkKeysOngoing,
  recovery,
  recoveryOngoing,
  dump,
  dumpOngoing,
  save
}

// cardExist true because we don't show error to user if nothing is done
class HFCardInfo {
  String uid;
  String sak;
  String atqa;
  String tech;
  String ats;
  TagType type;
  bool cardExist;

  HFCardInfo(
      {this.uid = '',
      this.sak = '',
      this.atqa = '',
      this.tech = '',
      this.ats = '',
      this.type = TagType.unknown,
      this.cardExist = true});
}

class LFCardInfo {
  LFCard? card;
  bool cardExist;

  LFCardInfo({this.cardExist = true});
}

class MifareClassicInfo {
  bool isEV1;
  MifareClassicRecovery? recovery;
  MifareClassicType type;
  MifareClassicState state;
  NTLevel? ntLevel;
  bool? hasBackdoor;

  MifareClassicInfo({
    MifareClassicRecovery? recovery,
    this.isEV1 = false,
    this.type = MifareClassicType.none,
    this.state = MifareClassicState.none,
    NTLevel? ntLevel,
    bool? hasBackdoor,
  });
}

class MifareUltralightInfo {
  Uint8List? version;
  Uint8List? signature;

  MifareUltralightInfo();
}

class ReadCardPage extends StatefulWidget {
  const ReadCardPage({super.key});

  @override
  ReadCardPageState createState() => ReadCardPageState();
}

class ReadCardPageState extends State<ReadCardPage> {
  String dumpName = "";
  HFCardInfo hfInfo = HFCardInfo();
  LFCardInfo lfInfo = LFCardInfo();
  MifareClassicInfo mfcInfo = MifareClassicInfo();
  MifareUltralightInfo mfuInfo = MifareUltralightInfo();

  bool isContinuousHFScan = false;
  bool isContinuousLFScan = false;
  bool scanInProgress = false;
  Timer? hfScanTimer;
  Timer? lfScanTimer;

  void updateMifareClassicRecovery() {
    setState(() {
      mfcInfo.recovery = mfcInfo.recovery;
    });
  }

  void updateMifareClassicInfo() {
    setState(() {
      mfcInfo = mfcInfo;
    });
  }

  Future<void> readLFInfo() async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

    setState(() {
      lfInfo = LFCardInfo();
    });

    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }

    LFCard? card = await appState.communicator!.readEM410X();
    card ??= await appState.communicator!.readHIDProx();
    card ??= await appState.communicator!.readViking();
    card ??= await appState.communicator!.readPac();
    card ??= await appState.communicator!.readIoProx();

    if (card != null) {
      setState(() {
        lfInfo.card = card;
        scanInProgress = false;
      });
    } else {
      setState(() {
        lfInfo.cardExist = false;
        scanInProgress = false;
      });
    }
  }

  Future<void> startContinuousHFScan() async {
    if (isContinuousHFScan) return;

    setState(() {
      isContinuousHFScan = true;
    });

    const scanInterval = Duration(seconds: 2);
    const maxDuration = Duration(minutes: 1);

    DateTime startTime = DateTime.now();

    hfScanTimer = Timer.periodic(scanInterval, (timer) async {
      if (DateTime.now().difference(startTime) > maxDuration || !mounted) {
        stopContinuousHFScan();
        return;
      }

      var info = await readHFInfo(context, updateMifareClassicRecovery);
      setState(() {
        hfInfo = info.$1;
        mfcInfo = info.$2;
        mfuInfo = info.$3;
      });

      if (hfInfo.cardExist && hfInfo.uid.isNotEmpty) {
        stopContinuousHFScan();
      }
    });

    var info = await readHFInfo(context, updateMifareClassicRecovery);
    setState(() {
      hfInfo = info.$1;
      mfcInfo = info.$2;
      mfuInfo = info.$3;
    });

    if (hfInfo.cardExist && hfInfo.uid.isNotEmpty) {
      stopContinuousHFScan();
    }
  }

  void stopContinuousHFScan() {
    if (hfScanTimer != null) {
      hfScanTimer?.cancel();
      hfScanTimer = null;

      if (mounted) {
        setState(() {
          isContinuousHFScan = false;
        });
      }
    }
  }

  Future<void> startContinuousLFScan() async {
    if (isContinuousLFScan) return;

    setState(() {
      isContinuousLFScan = true;
    });

    const scanInterval = Duration(seconds: 2);
    const maxDuration = Duration(minutes: 1);

    DateTime startTime = DateTime.now();

    lfScanTimer = Timer.periodic(scanInterval, (timer) async {
      if (DateTime.now().difference(startTime) > maxDuration || !mounted) {
        stopContinuousLFScan();
        return;
      }

      await readLFInfo();

      if (lfInfo.cardExist && lfInfo.card != null) {
        stopContinuousLFScan();
      }
    });

    await readLFInfo();
    if (lfInfo.cardExist && lfInfo.card != null) {
      stopContinuousLFScan();
    }
  }

  void stopContinuousLFScan() {
    if (lfScanTimer != null) {
      lfScanTimer?.cancel();
      lfScanTimer = null;

      if (mounted) {
        setState(() {
          isContinuousLFScan = false;
        });
      }
    }
  }

  @override
  void dispose() {
    stopContinuousHFScan();
    stopContinuousLFScan();
    super.dispose();
  }

  Future<void> saveHFCard() async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    var localizations = AppLocalizations.of(context)!;

    var tags = appState.sharedPreferencesProvider.getCards();
    tags.add(CardSave(
      uid: hfInfo.uid,
      sak: hexToBytes(hfInfo.sak)[0],
      atqa: hexToBytes(hfInfo.atqa),
      name: dumpName,
      tag: hfInfo.type != TagType.unknown ? hfInfo.type : TagType.mifare1K,
      data: [],
      ats: (hfInfo.ats != localizations.no)
          ? hexToBytes(hfInfo.ats)
          : Uint8List(0),
      extraData: CardSaveExtra(
        ultralightSignature: mfuInfo.signature,
        ultralightVersion: mfuInfo.version,
        ultralightCounters: [],
      ),
    ));

    appState.sharedPreferencesProvider.setCards(tags);
  }

  Future<void> saveLFCard() async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

    var tags = appState.sharedPreferencesProvider.getCards();
    tags.add(CardSave(
        uid: lfInfo.card.toString(), name: dumpName, tag: lfInfo.card!.type));
    appState.sharedPreferencesProvider.setCards(tags);
  }

  void _showLiteNotSupported() {
    var localizations = AppLocalizations.of(context)!;
    showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(localizations.no_supported),
        content: Text(localizations.lite_no_read,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, localizations.ok),
            child: Text(localizations.ok),
          ),
        ],
      ),
    );
  }

  /// Runs [scan] on an Ultra; a Lite gets the "not supported" dialog.
  Future<void> _runScan(Future<void> Function() scan) async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    if (appState.connector!.device == ChameleonDevice.ultra) {
      await scan();
    } else if (appState.connector!.device == ChameleonDevice.lite) {
      _showLiteNotSupported();
    } else {
      appState.changesMade();
    }
  }

  Future<void> _readHF() async {
    setState(() {
      scanInProgress = true;
    });
    try {
      var info = await readHFInfo(context, updateMifareClassicRecovery);
      if (!mounted) {
        return;
      }
      setState(() {
        hfInfo = info.$1;
        mfcInfo = info.$2;
        mfuInfo = info.$3;
      });
    } finally {
      if (mounted) {
        setState(() {
          scanInProgress = false;
        });
      }
    }
  }

  Future<void> _readLF() async {
    setState(() {
      scanInProgress = true;
    });
    try {
      await readLFInfo();
    } finally {
      if (mounted) {
        setState(() {
          scanInProgress = false;
        });
      }
    }
  }

  Widget _buildScanButtons({
    required bool isSmallScreen,
    required bool isContinuous,
    required Future<void> Function() onRead,
    required Future<void> Function() onStartContinuous,
    required VoidCallback onStopContinuous,
  }) {
    var localizations = AppLocalizations.of(context)!;

    final read = FilledButton.icon(
      onPressed: scanInProgress ? null : () => _runScan(onRead),
      icon: const Icon(Icons.sensors),
      label: Text(localizations.read),
    );
    final continuous = OutlinedButton.icon(
      onPressed:
          isContinuous ? onStopContinuous : () => _runScan(onStartContinuous),
      icon: Icon(isContinuous ? Icons.stop : Icons.repeat),
      label: Text(
          isContinuous ? localizations.cancel : localizations.continuous_scan),
    );

    if (isSmallScreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [read, const SizedBox(height: 8), continuous],
      );
    }

    return Row(
      children: [
        Expanded(child: read),
        const SizedBox(width: 12),
        Expanded(child: continuous),
      ],
    );
  }

  Widget buildFieldRow(String label, String value, double fontSize) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(fontSize: fontSize - 2, color: muted),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '—' : value,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    var localizations = AppLocalizations.of(context)!;
    final isSmallScreen = screenSize.width < 800;

    double fieldFontSize = isSmallScreen ? 16 : 20;

    var appState = context.watch<ChameleonGUIState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.read_card),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: localizations.antenna_guide_title,
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) => const AntennaGuideDialog(),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          localizations.hf_tag_info,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        buildFieldRow(
                            localizations.uid, hfInfo.uid, fieldFontSize),
                        buildFieldRow(
                            localizations.sak, hfInfo.sak, fieldFontSize),
                        buildFieldRow(
                            localizations.atqa, hfInfo.atqa, fieldFontSize),
                        buildFieldRow(
                            localizations.ats, hfInfo.ats, fieldFontSize),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${localizations.card_tech}: ${hfInfo.tech}',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: fieldFontSize),
                            ),
                            if (hfInfo.uid.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                        title: Text(
                                            localizations.override_card_type),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              localizations
                                                  .override_card_type_description,
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                            const SizedBox(height: 16),
                                            DropdownButton<TagType?>(
                                              isExpanded: true,
                                              value: hfInfo.type,
                                              onChanged:
                                                  (TagType? newValue) async {
                                                setState(() {
                                                  hfInfo.type = newValue!;
                                                  hfInfo.tech =
                                                      chameleonTagToString(
                                                          newValue,
                                                          localizations);
                                                });

                                                if (isMifareClassic(
                                                    newValue!)) {
                                                  var info =
                                                      await performMifareClassicScan(
                                                          appState
                                                              .communicator!,
                                                          mfcInfo,
                                                          context,
                                                          updateMifareClassicRecovery,
                                                          override: newValue);
                                                  setState(() {
                                                    mfcInfo = info.$2;
                                                  });
                                                } else if (isMifareUltralight(
                                                    newValue)) {
                                                  var info =
                                                      await performMifareUltralightScan(
                                                          appState
                                                              .communicator!,
                                                          mfuInfo,
                                                          override: newValue);
                                                  setState(() {
                                                    mfuInfo = info.$2;
                                                  });
                                                }

                                                if (context.mounted) {
                                                  Navigator.of(context).pop();
                                                }
                                              },
                                              items: [
                                                ...[
                                                  ...getTagTypesByFrequency(
                                                      TagFrequency.hf),
                                                  TagType.unknown
                                                ].map((TagType tagType) {
                                                  return DropdownMenuItem<
                                                      TagType?>(
                                                    value: tagType,
                                                    child: Text(
                                                        chameleonTagToString(
                                                            tagType,
                                                            localizations)),
                                                  );
                                                }),
                                              ],
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(),
                                            child: Text(localizations.cancel),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                                icon: const Icon(Icons.edit),
                                iconSize: 20,
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                tooltip: localizations.override_card_type,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (isMifareClassic(hfInfo.type)) ...[
                          if (mfcInfo.ntLevel != null)
                            buildFieldRow(
                                localizations.prng_type,
                                mfClassicGetPrngType(
                                    mfcInfo.ntLevel!, localizations),
                                fieldFontSize),
                          if (mfcInfo.hasBackdoor != null)
                            buildFieldRow(
                                localizations.has_backdoor_support,
                                mfcInfo.hasBackdoor!
                                    ? localizations.yes
                                    : localizations.no,
                                fieldFontSize),
                          const SizedBox(height: 16),
                        ],
                        _buildScanButtons(
                          isSmallScreen: isSmallScreen,
                          isContinuous: isContinuousHFScan,
                          onRead: _readHF,
                          onStartContinuous: startContinuousHFScan,
                          onStopContinuous: stopContinuousHFScan,
                        ),
                        if (!hfInfo.cardExist) ...[
                          const SizedBox(height: 16),
                          ErrorMessage(
                              errorMessage: localizations.no_card_found)
                        ],
                        if (hfInfo.uid != "") ...[
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () async {
                              await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title:
                                        Text(localizations.enter_name_of_card),
                                    content: TextField(
                                      onChanged: (value) {
                                        setState(() {
                                          dumpName = value;
                                        });
                                      },
                                    ),
                                    actions: [
                                      ElevatedButton(
                                        onPressed: () async {
                                          await saveHFCard();
                                          if (context.mounted) {
                                            Navigator.pop(context);
                                          }
                                        },
                                        child: Text(localizations.ok),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.pop(
                                              context); // Close the modal without saving
                                        },
                                        child: Text(localizations.cancel),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            style: customCardButtonStyle(appState),
                            child: Text(localizations.save_only_uid),
                          ),
                        ],
                        if (isMifareClassic(hfInfo.type))
                          MifareClassicHelper(mfcInfo: mfcInfo, hfInfo: hfInfo),
                        if (isMifareUltralight(hfInfo.type))
                          MifareUltralightHelper(hfInfo: hfInfo)
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          localizations.lf_tag_info,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        buildFieldRow(
                            localizations.uid,
                            lfInfo.card != null
                                ? lfInfo.card!.toViewableString()
                                : '',
                            fieldFontSize),
                        const SizedBox(height: 16),
                        Text(
                          '${localizations.card_tech}: ${(lfInfo.card != null ? chameleonTagToString(lfInfo.card!.type, localizations) : '')}',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: fieldFontSize),
                        ),
                        const SizedBox(height: 16),
                        _buildScanButtons(
                          isSmallScreen: isSmallScreen,
                          isContinuous: isContinuousLFScan,
                          onRead: _readLF,
                          onStartContinuous: startContinuousLFScan,
                          onStopContinuous: stopContinuousLFScan,
                        ),
                        if (!lfInfo.cardExist) ...[
                          const SizedBox(height: 16),
                          ErrorMessage(
                              errorMessage: localizations.no_card_found)
                        ],
                        if (lfInfo.card != null) ...[
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () async {
                              await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title:
                                        Text(localizations.enter_name_of_card),
                                    content: TextField(
                                      onChanged: (value) {
                                        setState(() {
                                          dumpName = value;
                                        });
                                      },
                                    ),
                                    actions: [
                                      ElevatedButton(
                                        onPressed: () async {
                                          await saveLFCard();
                                          if (context.mounted) {
                                            Navigator.pop(context);
                                          }
                                        },
                                        child: Text(localizations.ok),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          Navigator.pop(
                                              context); // Close the modal without saving
                                        },
                                        child: Text(localizations.cancel),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            style: customCardButtonStyle(appState),
                            child: Text(localizations.save),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
