import 'dart:async';

import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/component/ios_widgets.dart';
import 'package:chameleonultragui/gui/menu/dialogs/manual_connect.dart';
import 'package:chameleonultragui/helpers/flash.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class ConnectPage extends StatefulWidget {
  const ConnectPage({
    super.key,
    this.autoScanInterval = const Duration(seconds: 3),
  });

  final Duration autoScanInterval;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  List<Chameleon> _devices = [];
  Timer? _scanTimer;
  Object? _error;
  bool _isLoading = true;
  bool _initialScanCompleted = false;
  bool _scanInProgress = false;
  bool _connectionInProgress = false;
  bool _showedPermissionsSnackbar = false;
  dynamic _lastAutoConnectAttemptPort;

  ChameleonGUIState get _appState =>
      Provider.of<ChameleonGUIState>(context, listen: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanNow());
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    super.dispose();
  }

  bool _shouldScan(ChameleonGUIState appState) {
    return mounted &&
        !_connectionInProgress &&
        !appState.connector!.connected &&
        !appState.connector!.pendingConnection;
  }

  List<Chameleon> _normalizeDevices(List<Chameleon> devices) {
    final output = <Chameleon>[];
    final seen = <String>{};

    for (final device in devices) {
      final key = '${device.port}|${device.type.name}|${device.dfu}';
      if (seen.add(key)) {
        output.add(device);
      }
    }

    return output;
  }

  dynamic _firstConnectablePort(List<Chameleon> devices) {
    for (final device in devices) {
      if (!device.dfu) {
        return device.port;
      }
    }
    return null;
  }

  void _scheduleNextScan() {
    _scanTimer?.cancel();

    if (!_shouldScan(_appState) ||
        !_appState.sharedPreferencesProvider.getAutoScanEnabled()) {
      return;
    }

    _scanTimer = Timer(widget.autoScanInterval, _scanNow);
  }

  void _showPermissionsWarningIfNeeded(List<Chameleon> devices) {
    final appState = _appState;
    if (appState.connector is! AndroidSerial) {
      _showedPermissionsSnackbar = false;
      return;
    }

    final androidSerial = appState.connector as AndroidSerial;
    final shouldShow = devices.isEmpty && !androidSerial.hasAllPermissions;
    if (!shouldShow) {
      _showedPermissionsSnackbar = false;
      return;
    }

    if (_showedPermissionsSnackbar) {
      return;
    }

    _showedPermissionsSnackbar = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final scaffoldMessenger = ScaffoldMessenger.of(context);
      final localizations = AppLocalizations.of(context)!;
      final snackBar = SnackBar(
        content: Text(localizations.android_ble_permissions_missing),
        action: SnackBarAction(
          label: localizations.close,
          onPressed: () {},
        ),
      );

      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(snackBar);
    });
  }

  Future<void> _scanNow({bool manual = false}) async {
    final appState = _appState;
    if (_scanInProgress || !_shouldScan(appState)) {
      return;
    }

    _scanTimer?.cancel();

    setState(() {
      _scanInProgress = true;
      _error = null;
      if (!_initialScanCompleted || manual) {
        _isLoading = true;
      }
    });

    try {
      final devices = _normalizeDevices(
          await appState.connector!.availableChameleons(false));
      if (!mounted) {
        return;
      }

      appState.syncAutoReconnectSuppression(
        devices.map((device) => device.port),
      );

      final firstConnectablePort = _firstConnectablePort(devices);
      if (firstConnectablePort != _lastAutoConnectAttemptPort) {
        _lastAutoConnectAttemptPort = null;
      }

      setState(() {
        _devices = devices;
        _isLoading = false;
        _initialScanCompleted = true;
      });

      _showPermissionsWarningIfNeeded(devices);
      await _maybeAutoConnect(devices);
    } catch (error) {
      await appState.connector!.performDisconnect();
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error;
        _isLoading = false;
        _initialScanCompleted = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _scanInProgress = false;
        });
        _scheduleNextScan();
      }
    }
  }

  Future<void> _maybeAutoConnect(List<Chameleon> devices) async {
    final appState = _appState;
    if (!_shouldScan(appState) ||
        !appState.sharedPreferencesProvider.getAutoConnectFirstFoundDevice()) {
      return;
    }

    Chameleon? connectableDevice;
    for (final device in devices) {
      if (!device.dfu && !appState.isAutoReconnectSuppressed(device.port)) {
        connectableDevice = device;
        break;
      }
    }

    if (connectableDevice == null) {
      _lastAutoConnectAttemptPort = null;
      return;
    }

    if (_lastAutoConnectAttemptPort == connectableDevice.port) {
      return;
    }

    _lastAutoConnectAttemptPort = connectableDevice.port;
    await _connectToDevice(connectableDevice, fromAutoConnect: true);
  }

  Future<void> _connectToDevice(
    Chameleon chameleonDevice, {
    bool fromAutoConnect = false,
  }) async {
    final appState = _appState;

    if (_connectionInProgress) {
      return;
    }

    if (chameleonDevice.dfu) {
      if (!fromAutoConnect) {
        _showDfuDialog(chameleonDevice);
      }
      return;
    }

    _scanTimer?.cancel();
    if (mounted) {
      setState(() {
        _connectionInProgress = true;
      });
    }

    try {
      if (chameleonDevice.type == ConnectionType.ble) {
        appState.connector!.pendingConnection = true;
        appState.changesMade();
      }

      final connected =
          await appState.connector!.connectSpecificDevice(chameleonDevice.port);
      if (connected) {
        appState.connector!.pendingConnection = false;
        appState.clearAutoReconnectSuppression(chameleonDevice.port);
        appState.communicator =
            ChameleonCommunicator(appState.log!, port: appState.connector);
      } else {
        appState.connector!.pendingConnection = false;
      }

      appState.changesMade();
    } catch (error) {
      appState.connector!.pendingConnection = false;
      appState.changesMade();
      if (mounted) {
        setState(() {
          _error = error;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _connectionInProgress = false;
        });
      }

      if (!appState.connector!.connected) {
        _scheduleNextScan();
      }
    }
  }

  void _showDfuDialog(Chameleon chameleonDevice) {
    final appState = _appState;
    final localizations = AppLocalizations.of(context)!;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(localizations.chameleon_is_dfu),
        content: Text(localizations.firmware_is_corrupted),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, localizations.cancel),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext, localizations.flash);
              appState.changesMade();

              scaffoldMessenger.hideCurrentSnackBar();
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text(
                    localizations.downloading_fw(
                      chameleonDeviceName(chameleonDevice.device),
                    ),
                  ),
                  action: SnackBarAction(
                    label: localizations.close,
                    onPressed: scaffoldMessenger.hideCurrentSnackBar,
                  ),
                ),
              );

              await flashFirmware(
                appState,
                scaffoldMessenger: scaffoldMessenger,
                device: chameleonDevice.device,
                enterDFU: false,
              );

              appState.changesMade();
              if (mounted) {
                _scanNow();
              }
            },
            child: Text(localizations.flash),
          ),
        ],
      ),
    );
  }

  Widget _deviceImage(Chameleon chameleonDevice,
      {BoxFit fit = BoxFit.contain}) {
    return Image.asset(
      chameleonDevice.device == ChameleonDevice.ultra
          ? 'assets/black-ultra-standing-front.webp'
          : 'assets/black-lite-standing-front.webp',
      fit: fit,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  Widget _dfuBadge(AppLocalizations localizations) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        localizations.dfu,
        style: const TextStyle(
          color: Colors.orange,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// Phone layout: one full-width row per device with a thumbnail, name,
  /// port and a chevron.
  Widget _buildDeviceList(AppLocalizations localizations) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: _devices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) {
        final chameleonDevice = _devices[index];
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _connectionInProgress
                ? null
                : () => _connectToDevice(chameleonDevice),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    height: 76,
                    child: _deviceImage(chameleonDevice),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                "Chameleon ${chameleonDeviceName(chameleonDevice.device)}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (chameleonDevice.dfu) ...[
                              const SizedBox(width: 8),
                              _dfuBadge(localizations),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              chameleonDevice.type == ConnectionType.ble
                                  ? Icons.bluetooth
                                  : Icons.usb,
                              size: 16,
                              color: muted,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                chameleonDevice.port ?? "",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: muted),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: muted),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Wide layout: a grid of cards with the device render on top.
  Widget _buildDeviceGrid(AppLocalizations localizations) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.78,
      ),
      itemCount: _devices.length,
      itemBuilder: (BuildContext context, int index) {
        final chameleonDevice = _devices[index];
        return Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _connectionInProgress
                ? null
                : () => _connectToDevice(chameleonDevice),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _deviceImage(chameleonDevice)),
                  const SizedBox(height: 12),
                  Text(
                    "Chameleon ${chameleonDeviceName(chameleonDevice.device)}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        chameleonDevice.type == ConnectionType.ble
                            ? Icons.bluetooth
                            : Icons.usb,
                        size: 16,
                        color: muted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          chameleonDevice.port ?? "",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                      ),
                      if (chameleonDevice.dfu) _dfuBadge(localizations),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(AppLocalizations localizations) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.5);
    final autoScan = _appState.sharedPreferencesProvider.getAutoScanEnabled();

    return ListView(
      // Keep the page scrollable so pull-to-refresh works on an empty list.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 96),
      children: [
        Icon(Icons.devices_other, size: 72, color: muted),
        const SizedBox(height: 20),
        Text(
          localizations.no_devices_found,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          localizations.no_devices_hint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: muted),
        ),
        const SizedBox(height: 24),
        if (autoScan)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AdaptiveProgress(radius: 8),
              const SizedBox(width: 10),
              Text(
                localizations.searching_for_devices,
                style: TextStyle(fontSize: 13, color: muted),
              ),
            ],
          )
        else
          Center(
            child: OutlinedButton.icon(
              onPressed: () => _scanNow(manual: true),
              icon: const Icon(Icons.refresh),
              label: Text(localizations.retry),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;
    final isPhone = MediaQuery.of(context).size.width < 600;

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(localizations.connect),
        ),
        body: ErrorPage(errorMessage: _error.toString()),
      );
    }

    final Widget body;
    if (_isLoading && !_initialScanCompleted) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AdaptiveProgress(radius: 14),
            const SizedBox(height: 16),
            Text(
              localizations.searching_for_devices,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      );
    } else if (_devices.isEmpty) {
      body = _buildEmptyState(localizations);
    } else if (isPhone) {
      body = _buildDeviceList(localizations);
    } else {
      body = _buildDeviceGrid(localizations);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.connect),
        actions: [
          if (_scanInProgress && _initialScanCompleted)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: AdaptiveProgress(radius: 9),
            )
          else
            IconButton(
              tooltip: localizations.retry,
              onPressed: () => _scanNow(manual: true),
              icon: const Icon(Icons.refresh),
            ),
        ],
        bottom: _connectionInProgress
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: () => _scanNow(manual: true),
        child: body,
      ),
      floatingActionButton: appState.connector!.isManualConnectionSupported()
          ? FloatingActionButton.extended(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (BuildContext dialogContext) => const ManualConnect(),
              ),
              icon: const Icon(Icons.add),
              label: Text(localizations.connect_manually),
            )
          : null,
    );
  }
}
