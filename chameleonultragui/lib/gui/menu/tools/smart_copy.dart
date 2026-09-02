import 'dart:typed_data';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/feedback.dart' as feedback;
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/helpers/slot_write.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

enum CopyStage { idle, reading, writing, done, error }

/// One-tap "clone a physical card": read the card on the reader, pick a free
/// slot, write it there and start emulating — no manual slot picking or type
/// selection.
///
/// For Mifare Classic the read step now runs the full key-recovery pipeline —
/// every key from the user's dictionaries plus the built-in defaults, then a
/// nested/hardnested crack for whatever is left — and dumps the sectors it can
/// read, so the clone carries real sector data, not just the UID. Sectors whose
/// keys could not be recovered are cloned as zero blocks; if nothing at all can
/// be read the flow falls back to a UID-only clone, which still opens UID-based
/// access systems.
class SmartCopyMenu extends StatefulWidget {
  const SmartCopyMenu({super.key});

  @override
  SmartCopyMenuState createState() => SmartCopyMenuState();
}

class SmartCopyMenuState extends State<SmartCopyMenu> {
  CopyStage stage = CopyStage.idle;
  int progress = 0;
  String? resultMessage;
  String? errorMessage;
  String? subStatus;

  Future<int> _firstFreeSlot(ChameleonGUIState appState) async {
    final enabled = await appState.communicator!.getEnabledSlots();
    for (int i = 0; i < enabled.length; i++) {
      if (!enabled[i].any()) {
        return i;
      }
    }
    // All slots busy — fall back to the currently active one.
    return appState.communicator!.getActiveSlot();
  }

  /// Runs the full Mifare Classic recovery on the card sitting on the reader
  /// and returns its per-block dump (256-entry list; unreadable blocks are
  /// zeroed). The card must stay on the antenna for the whole call.
  Future<List<Uint8List>> _recoverClassicData(
      ChameleonGUIState appState, AppLocalizations localizations) async {
    late final MifareClassicRecovery recovery;
    recovery = MifareClassicRecovery(
      appState: appState,
      localizations: localizations,
      update: () {
        if (mounted) {
          setState(() {
            subStatus = recovery.state.isNotEmpty ? recovery.state : null;
            if (recovery.dumpProgress > 0) {
              progress = (recovery.dumpProgress * 100).round();
            }
          });
        }
      },
    );

    await recovery.initialize();

    // Try every key the user has stored, plus the built-in defaults that
    // checkKeys() always appends. Merge all 6-byte dictionaries into one so a
    // single pass covers them all (the manual UI only lets you pick one).
    final stored =
        appState.sharedPreferencesProvider.getDictionaries(keyLength: 12);
    final mergedKeys = <Uint8List>[];
    for (final dictionary in stored) {
      mergedKeys.addAll(dictionary.keys);
    }
    recovery.dictionaries = [
      Dictionary(id: "smart_copy", name: localizations.smart_copy, keys: mergedKeys)
    ];
    recovery.selectedDictionary = recovery.dictionaries.first;

    // 1) Dictionary + default keys (fast).
    await recovery.checkKeys();

    // 2) Crack whatever is still unknown (nested / hardnested). Slow, and may
    //    fail on hardened sectors — keep the keys we already have either way.
    if (!recovery.allKeysExists) {
      try {
        await recovery.recoverKeys();
      } catch (_) {
        // Ignore: dump proceeds with the keys recovered so far.
      }
    }

    // 3) Read every sector we hold a key for.
    await recovery.dumpData();

    if (mounted) {
      setState(() => subStatus = null);
    }
    return recovery.cardData;
  }

  Future<CardSave?> _readCard(
      ChameleonGUIState appState, AppLocalizations localizations) async {
    // Try high frequency first.
    final info = await readHFInfo(context, () {});
    final hf = info.$1;
    final mfu = info.$3;
    if (hf.cardExist && hf.uid.isNotEmpty) {
      // For Mifare Classic, recover the keys and dump the sectors so the clone
      // carries real data (needed by readers that authenticate sectors, not
      // just the UID). Best effort — on any failure we keep the UID-only clone.
      List<Uint8List> data = const [];
      if (isMifareClassic(hf.type)) {
        try {
          data = await _recoverClassicData(appState, localizations);
        } catch (_) {
          data = const [];
        }
      }

      return CardSave(
        uid: hf.uid,
        sak: hexToBytes(hf.sak)[0],
        atqa: hexToBytes(hf.atqa),
        name: "${localizations.smart_copy} ${hf.uid}",
        tag: hf.type != TagType.unknown ? hf.type : TagType.mifare1K,
        data: data,
        ats: (hf.ats != localizations.no)
            ? hexToBytes(hf.ats)
            : Uint8List(0),
        extraData: CardSaveExtra(
          ultralightSignature: mfu.signature,
          ultralightVersion: mfu.version,
          ultralightCounters: const [],
        ),
      );
    }

    // Then low frequency.
    if (!await appState.communicator!.isReaderDeviceMode()) {
      await appState.communicator!.setReaderDeviceMode(true);
    }
    LFCard? lfCard = await appState.communicator!.readEM410X();
    lfCard ??= await appState.communicator!.readHIDProx();
    lfCard ??= await appState.communicator!.readViking();
    lfCard ??= await appState.communicator!.readPac();
    lfCard ??= await appState.communicator!.readIoProx();
    if (lfCard != null) {
      return CardSave(
        uid: lfCard.toString(),
        name: "${localizations.smart_copy} ${lfCard.toString()}",
        tag: lfCard.type,
      );
    }

    return null;
  }

  Future<void> _start() async {
    final appState = context.read<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;

    setState(() {
      stage = CopyStage.reading;
      progress = 0;
      resultMessage = null;
      errorMessage = null;
      subStatus = null;
    });

    try {
      final card = await _readCard(appState, localizations);
      if (card == null) {
        feedback.AppFeedback.error();
        setState(() {
          stage = CopyStage.error;
          errorMessage = localizations.smart_copy_no_card;
        });
        return;
      }

      final slot = await _firstFreeSlot(appState);

      setState(() {
        stage = CopyStage.writing;
      });

      await writeCardToSlot(
        communicator: appState.communicator!,
        slot: slot,
        card: card,
        noName: localizations.no_name,
        onProgress: (value) {
          if (mounted) {
            setState(() => progress = value);
          }
        },
      );

      // Keep a copy in the saved cards list too.
      final cards = appState.sharedPreferencesProvider.getCards();
      cards.add(card);
      appState.sharedPreferencesProvider.setCards(cards);
      appState.changesMade();

      feedback.AppFeedback.success();
      setState(() {
        stage = CopyStage.done;
        resultMessage = localizations.smart_copy_done(slot + 1);
      });
    } on UnsupportedError {
      feedback.AppFeedback.error();
      setState(() {
        stage = CopyStage.error;
        errorMessage = localizations.smart_copy_unsupported;
      });
    } catch (error) {
      feedback.AppFeedback.error();
      setState(() {
        stage = CopyStage.error;
        errorMessage = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final appState = context.watch<ChameleonGUIState>();
    final connected = appState.connector?.connected ?? false;
    final busy = stage == CopyStage.reading || stage == CopyStage.writing;

    return AlertDialog(
      title: Text(localizations.smart_copy),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              localizations.smart_copy_hint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            if (stage == CopyStage.idle)
              const Icon(Icons.copy_all, size: 64, color: Colors.grey),
            if (stage == CopyStage.reading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(localizations.smart_copy_reading),
              if (subStatus != null) ...[
                const SizedBox(height: 6),
                Text(
                  subStatus!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
            if (stage == CopyStage.writing) ...[
              LinearProgressIndicator(value: progress / 100),
              const SizedBox(height: 12),
              Text("${localizations.smart_copy_writing} $progress%"),
            ],
            if (stage == CopyStage.done) ...[
              const Icon(Icons.check_circle, size: 64, color: Colors.green),
              const SizedBox(height: 12),
              Text(resultMessage ?? "",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
            if (stage == CopyStage.error) ...[
              const Icon(Icons.error, size: 64, color: Colors.orange),
              const SizedBox(height: 12),
              Text(errorMessage ?? "", textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: Text(localizations.close),
        ),
        if (stage != CopyStage.done)
          FilledButton.icon(
            onPressed: (!connected || busy) ? null : _start,
            icon: const Icon(Icons.copy),
            label: Text(stage == CopyStage.error
                ? localizations.retry
                : localizations.smart_copy_start),
          ),
      ],
    );
  }
}
