import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/component/ios_widgets.dart';
import 'package:chameleonultragui/gui/menu/dialogs/chameleon_settings.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/gui/component/slot_changer.dart';
import 'dart:math';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

typedef _HomeData = ({
  IconData batteryIcon,
  BatteryCharge battery,
  String usedSlots,
  List<String> fwVersion,
  bool isReaderDeviceMode,
  bool areCapabilitiesSupported,
});

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  bool isLegacyFirmware = false;
  Future<_HomeData>? _future;

  Future<_HomeData> _getFutureData() async {
    var appState = context.read<ChameleonGUIState>();
    List<SlotTypes> slotTypes = [];
    try {
      slotTypes = await appState.communicator!.getSlotTagTypes();
    } catch (e) {
      appState.log!.e(e);
    }

    final battery = await getBatteryInfo();
    return (
      batteryIcon: battery.$1,
      battery: battery.$2,
      usedSlots: await getUsedSlotsOut8(slotTypes),
      fwVersion: await getVersion(),
      isReaderDeviceMode: await isReaderDeviceMode(),
      areCapabilitiesSupported: await areCapabilitiesSupported(),
    );
  }

  void _reload() {
    setState(() {
      _future = _getFutureData();
    });
  }

  Future<bool> areCapabilitiesSupported() async {
    // Checks that firmware supports all functions of current app
    // If not, prompt user to update firmware (as outdated firmware might break app)

    int ultraCapability = ChameleonCommand.setIdteckEmulatorID.value;
    int liteCapability = ChameleonCommand.setIdteckEmulatorID.value;

    var appState = context.read<ChameleonGUIState>();
    List<int> capabilities;
    try {
      capabilities = await appState.communicator!.getDeviceCapabilities();
    } catch (_) {
      return false;
    }

    if (appState.connector!.device == ChameleonDevice.ultra &&
        !capabilities.contains(ultraCapability)) {
      return false;
    }

    if (appState.connector!.device == ChameleonDevice.lite &&
        !capabilities.contains(liteCapability)) {
      return false;
    }

    return true;
  }

  Future<(IconData, BatteryCharge)> getBatteryInfo() async {
    var appState = context.read<ChameleonGUIState>();
    IconData icon = Icons.battery_unknown;
    BatteryCharge battery = BatteryCharge(percent: 0, voltage: 0);

    try {
      battery = await appState.communicator!.getBatteryCharge();
    } catch (_) {}

    if (battery.percent > 98) {
      icon = Icons.battery_full;
    } else if (battery.percent > 87) {
      icon = Icons.battery_6_bar;
    } else if (battery.percent > 75) {
      icon = Icons.battery_5_bar;
    } else if (battery.percent > 62) {
      icon = Icons.battery_4_bar;
    } else if (battery.percent > 50) {
      icon = Icons.battery_3_bar;
    } else if (battery.percent > 37) {
      icon = Icons.battery_2_bar;
    } else if (battery.percent > 10) {
      icon = Icons.battery_1_bar;
    } else if (battery.percent > 3) {
      icon = Icons.battery_0_bar;
    } else if (battery.percent > 0) {
      icon = Icons.battery_alert;
    }

    return (icon, battery);
  }

  Future<String> getUsedSlotsOut8(List<SlotTypes> slotTypes) async {
    int usedSlotsOut8 = 0;

    if (slotTypes.isEmpty) {
      return AppLocalizations.of(context)!.unknown;
    }

    for (int i = 0; i < 8; i++) {
      if (slotTypes[i].notMatch()) {
        usedSlotsOut8++;
      }
    }
    return usedSlotsOut8.toString();
  }

  Future<List<String>> getVersion() async {
    var appState = context.read<ChameleonGUIState>();

    String commitHash = "";
    var firmware = await appState.communicator!.getFirmwareVersion();
    isLegacyFirmware = firmware.legacyProtocol;
    String firmwareVersion = numToVerCode(firmware.version);

    try {
      commitHash = await appState.communicator!.getGitCommitHash();
    } catch (_) {}

    if (commitHash.isEmpty) {
      if (mounted) {
        commitHash = AppLocalizations.of(context)!.outdated_fw;
      } else {
        commitHash = "Outdated FW";
      }
    }

    if (mounted && isLegacyFirmware) {
      var localizations = AppLocalizations.of(context)!;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(localizations.outdated_protocol),
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text(localizations.outdated_protocol_description_1),
                  Text(localizations.outdated_protocol_description_2),
                  Text(localizations.outdated_protocol_description_3),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(localizations.update),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _flashLatestFirmware();
                },
              ),
              TextButton(
                child: Text(localizations.skip),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }

    return ["$firmwareVersion ($commitHash)", commitHash];
  }

  Future<bool> isReaderDeviceMode() async {
    var appState = context.read<ChameleonGUIState>();
    return await appState.communicator!.isReaderDeviceMode();
  }

  /// Downloads and flashes the latest firmware, with the usual snackbar.
  Future<void> _flashLatestFirmware() async {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    var scaffoldMessenger = ScaffoldMessenger.of(context);

    scaffoldMessenger.hideCurrentSnackBar();
    scaffoldMessenger.showSnackBar(SnackBar(
      content: Text(localizations
          .downloading_fw(chameleonDeviceName(appState.connector!.device))),
      action: SnackBarAction(
        label: localizations.close,
        onPressed: scaffoldMessenger.hideCurrentSnackBar,
      ),
    ));

    try {
      await flashFirmware(appState, scaffoldMessenger: scaffoldMessenger);
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text('${localizations.update_error}: ${e.toString()}'),
        action: SnackBarAction(
          label: localizations.close,
          onPressed: scaffoldMessenger.hideCurrentSnackBar,
        ),
      ));
    }
  }

  Future<void> _checkForUpdates(List<String> fwVersion) async {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    var scaffoldMessenger = ScaffoldMessenger.of(context);
    String latestCommit;

    try {
      latestCommit = await latestAvailableCommit(appState.connector!.device);
    } catch (e) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text('${localizations.update_error}: ${e.toString()}'),
        action: SnackBarAction(
          label: localizations.close,
          onPressed: () {},
        ),
      ));
      return;
    }

    try {
      fwVersion[1] = await resolveCommit(fwVersion[1]);
    } catch (_) {}

    appState.log!
        .i("Latest commit: $latestCommit, current commit ${fwVersion[1]}");

    if (latestCommit.isEmpty) {
      return;
    }

    if (latestCommit.startsWith(fwVersion[1])) {
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text(localizations
            .up_to_date(chameleonDeviceName(appState.connector!.device))),
        action: SnackBarAction(
          label: localizations.close,
          onPressed: () {},
        ),
      ));
    } else {
      await _flashLatestFirmware();
    }
  }

  Future<void> _setReaderMode(bool reader) async {
    var appState = context.read<ChameleonGUIState>();
    try {
      await appState.communicator!.setReaderDeviceMode(reader);
    } catch (e) {
      appState.log!.e(e);
    }
    if (!mounted) {
      return;
    }
    _reload();
    appState.changesMade();
  }

  Color _batteryColor(int percent, ThemeData theme) {
    if (percent > 50) {
      return const Color(0xFF34C759);
    } else if (percent > 20) {
      return Colors.orange;
    } else if (percent > 0) {
      return theme.colorScheme.error;
    }
    return theme.colorScheme.onSurface.withValues(alpha: 0.5);
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    _future ??= _getFutureData();

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.home),
        actions: [
          IconButton(
            tooltip: localizations.device_settings,
            icon: const Icon(Icons.tune),
            onPressed: () => showDialog<String>(
                context: context,
                builder: (BuildContext dialogContext) =>
                    const ChameleonSettings()),
          ),
        ],
      ),
      body: FutureBuilder<_HomeData>(
          future: _future,
          builder: (BuildContext context, AsyncSnapshot<_HomeData> snapshot) {
            if (snapshot.hasError) {
              appState.disconnect();
              return Center(
                  child: ErrorPage(errorMessage: snapshot.error.toString()));
            }

            if (!snapshot.hasData) {
              return const Center(child: AdaptiveProgress());
            }

            return _buildBody(context, appState, localizations, snapshot.data!);
          }),
    );
  }

  Widget _buildBody(BuildContext context, ChameleonGUIState appState,
      AppLocalizations localizations, _HomeData data) {
    final theme = Theme.of(context);
    final isDemo = appState.connector!.portName == "Demo";
    final isBle = appState.connector!.connectionType == ConnectionType.ble;
    final deviceName =
        "Chameleon ${chameleonDeviceName(appState.connector!.device)}";
    final imageHeight = min(MediaQuery.of(context).size.height * 0.26, 240.0);
    final batteryColor = _batteryColor(data.battery.percent, theme);

    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        try {
          await _future;
        } catch (_) {}
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 32),
            children: [
              // Hero: device render, name and connection chips.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Image.asset(
                      appState.connector!.device == ChameleonDevice.ultra
                          ? 'assets/black-ultra-standing-front.webp'
                          : 'assets/black-lite-standing-front.webp',
                      height: imageHeight,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      deviceName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          icon: isBle ? Icons.bluetooth : Icons.usb,
                          label: appState.connector!.portName,
                        ),
                        Tooltip(
                          message: localizations.battery_info(
                              data.battery.percent, data.battery.voltage),
                          child: _InfoChip(
                            icon: data.batteryIcon,
                            iconColor: batteryColor,
                            label: '${data.battery.percent}%',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (isDemo)
                _Banner(
                  icon: Icons.info_outline,
                  text: localizations.demo_firmware,
                ),
              if (!data.areCapabilitiesSupported && !isDemo)
                _Banner(
                  icon: Icons.system_update_alt,
                  text: localizations.please_update_firmware,
                  action: TextButton(
                    onPressed: _flashLatestFirmware,
                    child: Text(localizations.update),
                  ),
                ),

              // Slots
              IosListSection(
                header: localizations.active_slot,
                footer: localizations.tap_slot_to_activate,
                children: const [
                  Padding(
                    padding: EdgeInsets.fromLTRB(10, 12, 10, 12),
                    child: SlotChanger(),
                  ),
                ],
              ),

              // Status
              IosListSection(
                header: localizations.status,
                children: [
                  ListTile(
                    leading: Icon(data.batteryIcon, color: batteryColor),
                    title: Text(localizations.battery),
                    subtitle: Text('${data.battery.voltage} mV'),
                    trailing: Text(
                      '${data.battery.percent}%',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.widgets_outlined),
                    title: Text(localizations.used_slots),
                    trailing: Text(
                      '${data.usedSlots} / 8',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (!isDemo)
                    ListTile(
                      leading: const Icon(Icons.memory),
                      title: Text(localizations.firmware_version),
                      subtitle: Text(data.fwVersion[0]),
                      trailing: IconButton(
                        tooltip: localizations.check_updates,
                        icon: const Icon(Icons.update),
                        onPressed: () => _checkForUpdates(data.fwVersion),
                      ),
                    ),
                ],
              ),

              // Mode
              IosListSection(
                header: localizations.mode,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: false,
                            icon: const Icon(Icons.nfc),
                            label: Text(localizations.emulator_mode),
                          ),
                          ButtonSegment(
                            value: true,
                            icon: const Icon(Icons.contactless_outlined),
                            label: Text(localizations.reader_mode),
                          ),
                        ],
                        selected: {data.isReaderDeviceMode},
                        onSelectionChanged: (selection) =>
                            _setReaderMode(selection.first),
                      ),
                    ),
                  ),
                ],
              ),

              // Disconnect
              IosListSection(
                children: [
                  ListTile(
                    leading:
                        Icon(Icons.link_off, color: theme.colorScheme.error),
                    title: Text(
                      localizations.disconnect,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () async {
                      await appState.disconnect(manual: true);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small rounded pill with an icon and a label, used for the port and battery.
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;

  const _InfoChip({required this.icon, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: iconColor ?? muted),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: muted),
          ),
        ],
      ),
    );
  }
}

/// Tinted inline notice (demo firmware, outdated firmware).
class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Banner({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    const tint = Colors.orange;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: tint),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14)),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
