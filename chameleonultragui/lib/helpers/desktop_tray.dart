import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

/// System tray / menu bar icon for desktop platforms. Shows the live
/// connection status and offers quick slot activation without opening the
/// window. All slot changes go through [onActivateSlot] which the owner wires
/// to the live communicator; the tray runs in the same isolate so this is a
/// plain callback.
class DesktopTray with TrayListener {
  void Function(int slot)? onActivateSlot;
  VoidCallback? onQuit;

  bool _initialized = false;
  bool? _lastConnected;

  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> init() async {
    if (!isSupported || _initialized) {
      return;
    }
    _initialized = true;
    trayManager.addListener(this);
    await trayManager.setIcon('assets/logo.png');
    await trayManager.setToolTip('Chameleon Ultra GUI');
  }

  /// Rebuilds the tray menu when the connection state changes. Cheap to call on
  /// every rebuild; only touches the OS when [connected] actually changed.
  Future<void> sync({required bool connected}) async {
    if (!isSupported || !_initialized || _lastConnected == connected) {
      return;
    }
    _lastConnected = connected;

    final menu = Menu(
      items: [
        MenuItem(
          key: 'status',
          label: connected ? 'Connected' : 'Disconnected',
          disabled: true,
        ),
        MenuItem.separator(),
        if (connected)
          MenuItem.submenu(
            key: 'slots',
            label: 'Activate slot',
            submenu: Menu(
              items: [
                for (int i = 0; i < 8; i++)
                  MenuItem(key: 'slot_$i', label: 'Slot ${i + 1}'),
              ],
            ),
          ),
        if (connected) MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Quit'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key ?? '';
    if (key == 'quit') {
      onQuit?.call();
    } else if (key.startsWith('slot_')) {
      final slot = int.tryParse(key.substring('slot_'.length));
      if (slot != null) {
        onActivateSlot?.call(slot);
      }
    }
  }

  void dispose() {
    if (_initialized) {
      trayManager.removeListener(this);
      _initialized = false;
    }
  }
}
