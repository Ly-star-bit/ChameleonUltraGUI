import 'dart:io';
import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:chameleonultragui/connector/serial_android.dart';
import 'package:chameleonultragui/connector/serial_ble.dart';
import 'package:chameleonultragui/connector/serial_emulator.dart';
import 'package:chameleonultragui/connector/serial_macos.dart';
import 'package:chameleonultragui/gui/page/tools.dart';
import 'package:chameleonultragui/helpers/desktop_tray.dart';
import 'package:chameleonultragui/helpers/feedback.dart';
import 'package:chameleonultragui/helpers/font.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/ios_theme.dart';
import 'package:chameleonultragui/helpers/location_slot.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'connector/serial_native.dart';

// Page imports
import 'package:chameleonultragui/gui/page/home.dart';
import 'package:chameleonultragui/gui/page/saved_cards.dart';
import 'package:chameleonultragui/gui/page/settings.dart';
import 'package:chameleonultragui/gui/page/connect.dart';
import 'package:chameleonultragui/gui/page/debug.dart';
import 'package:chameleonultragui/gui/page/slot_manager.dart';
import 'package:chameleonultragui/gui/page/flashing.dart';
import 'package:chameleonultragui/gui/page/read_card.dart';
import 'package:chameleonultragui/gui/page/write_card.dart';
import 'package:chameleonultragui/gui/page/pending_connection.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

// Shared Preferences Provider
import 'package:chameleonultragui/sharedprefsprovider.dart';

// Logger
import 'package:logger/logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sharedPreferencesProvider = SharedPreferencesProvider();
  await sharedPreferencesProvider.load();
  runApp(ChameleonGUI(sharedPreferencesProvider));
}

class ChameleonGUI extends StatelessWidget {
  // Root Widget
  final SharedPreferencesProvider _sharedPreferencesProvider;
  const ChameleonGUI(this._sharedPreferencesProvider, {super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _sharedPreferencesProvider),
        ChangeNotifierProvider(
          create: (context) => ChameleonGUIState(_sharedPreferencesProvider),
        ),
      ],
      child: MainPage(sharedPreferencesProvider: _sharedPreferencesProvider),
    );
  }
}

class ChameleonGUIState extends ChangeNotifier {
  final SharedPreferencesProvider sharedPreferencesProvider;
  ChameleonGUIState(this.sharedPreferencesProvider);

  SharedPreferencesProvider? _sharedPreferencesProvider;
  Logger? log; // Logger

  // Android uses AndroidSerial, iOS can only use BLESerial
  // The rest (desktops?) can use NativeSerial
  AbstractSerial? connector;
  ChameleonCommunicator? communicator;

  bool devMode = false;
  double? progress; // DFU

  // Flashing easter egg
  bool easterEgg = false;
  dynamic _suppressedAutoReconnectPort;

  GlobalKey navigationRailKey = GlobalKey();
  Size? navigationRailSize;

  LocationSlotMonitor? locationMonitor;

  void changesMade() {
    notifyListeners();
  }

  LocationSlotMonitor ensureLocationMonitor() {
    return locationMonitor ??= LocationSlotMonitor(
      prefs: sharedPreferencesProvider,
      activateSlot: (slot) async {
        if (communicator != null && (connector?.connected ?? false)) {
          await communicator!.activateSlot(slot);
        }
      },
      isConnected: () =>
          communicator != null && (connector?.connected ?? false),
      log: log,
    );
  }

  Future<bool> startLocationMonitor(
      {String? notificationTitle, String? notificationText}) async {
    return ensureLocationMonitor().start(
      notificationTitle: notificationTitle,
      notificationText: notificationText,
    );
  }

  void stopLocationMonitor() {
    locationMonitor?.stop();
  }

  void startScheduleMonitor() {
    ensureLocationMonitor().startSchedule();
  }

  void stopScheduleMonitor() {
    locationMonitor?.stopSchedule();
  }

  bool _wasConnected = false;

  void onConnectorStateChanged() {
    if (connector == null || !connector!.connected) {
      communicator = null;
      progress = null;
    }

    final isConnected = connector?.connected ?? false;
    if (isConnected != _wasConnected) {
      if (isConnected) {
        AppFeedback.success();
      } else {
        AppFeedback.error();
      }
      _wasConnected = isConnected;
    }

    notifyListeners();
  }

  bool isAutoReconnectSuppressed(dynamic devicePort) {
    return _suppressedAutoReconnectPort == devicePort;
  }

  void clearAutoReconnectSuppression([dynamic devicePort]) {
    if (devicePort == null || _suppressedAutoReconnectPort == devicePort) {
      _suppressedAutoReconnectPort = null;
    }
  }

  void syncAutoReconnectSuppression(Iterable<dynamic> visiblePorts) {
    if (_suppressedAutoReconnectPort == null) {
      return;
    }

    for (final port in visiblePorts) {
      if (port == _suppressedAutoReconnectPort) {
        return;
      }
    }

    _suppressedAutoReconnectPort = null;
  }

  Future<void> disconnect({bool manual = false}) async {
    final suppressedPort = manual ? connector?.activeDevicePort : null;
    await connector?.performDisconnect();
    if (manual && suppressedPort != null) {
      _suppressedAutoReconnectPort = suppressedPort;
    }
    communicator = null;
    progress = null;
    notifyListeners();
  }

  void setProgressBar(dynamic value) {
    progress = value;
    notifyListeners();
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key, required this.sharedPreferencesProvider});

  final SharedPreferencesProvider sharedPreferencesProvider;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  var selectedIndex = 0;
  bool _navHidden = false;
  DesktopTray? _tray;

  Widget _collapsedNavStrip(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        width: 44,
        child: Align(
          alignment: Alignment.topCenter,
          child: IconButton(
            icon: const Icon(Icons.menu),
            tooltip: AppLocalizations.of(context)!.more,
            onPressed: () => setState(() => _navHidden = false),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => updateNavigationRailWidth(context));

    if (DesktopTray.isSupported) {
      final tray = DesktopTray();
      _tray = tray;
      tray.onQuit = () => exit(0);
      tray.onActivateSlot = (slot) {
        final appState = Provider.of<ChameleonGUIState>(context, listen: false);
        if (appState.communicator != null &&
            (appState.connector?.connected ?? false)) {
          appState.communicator!.activateSlot(slot);
        }
      };
      tray.init();
    }
  }

  @override
  void dispose() {
    _tray?.dispose();
    super.dispose();
  }

  @override
  void reassemble() async {
    // Disconnect on reload
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    await appState.disconnect();

    super.reassemble();
  }

  AbstractSerial getConnector(ChameleonGUIState appState) {
    if (appState._sharedPreferencesProvider!.isEmulatedChameleon()) {
      return EmulatorSerial(log: appState.log!);
    }

    if (Platform.isMacOS) {
      return MacOSSerial(log: appState.log!);
    }

    if (Platform.isAndroid) {
      return AndroidSerial(log: appState.log!);
    }

    if (Platform.isIOS) {
      return BLESerial(log: appState.log!);
    }

    return NativeSerial(log: appState.log!);
  }

  Logger getLogger(ChameleonGUIState appState) {
    if (appState._sharedPreferencesProvider!.isDebugLogging() &&
        appState._sharedPreferencesProvider!.isDebugMode()) {
      return Logger(
        output: SharedPreferencesLogger(appState._sharedPreferencesProvider!),
        printer: PrettyPrinter(
          noBoxingByDefault: true,
        ),
        filter: ChameleonLogFilter(),
      );
    } else {
      return Logger();
    }
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    appState._sharedPreferencesProvider = widget.sharedPreferencesProvider;
    appState.log ??= getLogger(appState);
    appState.connector ??= getConnector(appState);
    appState.connector!.connectionStateCallback =
        appState.onConnectorStateChanged;

    if (appState.sharedPreferencesProvider.getSideBarAutoExpansion()) {
      double width = MediaQuery.of(context).size.width;
      if (width >= 600) {
        appState.sharedPreferencesProvider.setSideBarExpanded(true);
      } else {
        appState.sharedPreferencesProvider.setSideBarExpanded(false);
      }
    }

    appState.devMode = appState.sharedPreferencesProvider.isDebugMode();

    // Location based slot switching only makes sense on mobile (GPS). Keep the
    // monitor in sync with the saved preference on every rebuild; start() is
    // idempotent so this is cheap.
    if (Platform.isAndroid || Platform.isIOS) {
      if (appState.sharedPreferencesProvider.getLocationSwitchEnabled()) {
        // MainPage sits above MaterialApp, so AppLocalizations.of(context) is
        // not available here; look it up directly for the notification text.
        final loc = lookupAppLocalizations(
            widget.sharedPreferencesProvider.getLocale());
        appState.startLocationMonitor(
          notificationTitle: loc.location_slots,
          notificationText: loc.location_running_notification,
        );
      } else {
        appState.stopLocationMonitor();
      }

      if (appState.sharedPreferencesProvider.getScheduleSwitchEnabled()) {
        appState.startScheduleMonitor();
      } else {
        appState.stopScheduleMonitor();
      }
    }

    _tray?.sync(connected: appState.connector!.connected);

    Widget page; // Set Page
    if (!appState.connector!.connected &&
        selectedIndex != 0 &&
        selectedIndex != 2 &&
        selectedIndex != 5 &&
        selectedIndex != 6 &&
        selectedIndex != 7) {
      // If not connected, and not on home, tools, settings or dev page, go to home page
      selectedIndex = 0;
    }

    switch (selectedIndex) {
      // Sidebar Navigation
      case 0:
        if (appState.connector!.pendingConnection) {
          page = const PendingConnectionPage();
        } else {
          if (appState.connector!.connected) {
            if (appState.connector!.isDFU) {
              page = const FlashingPage();
            } else {
              page = const HomePage();
            }
          } else {
            page = const ConnectPage();
          }
        }
        break;
      case 1:
        page = const SlotManagerPage();
        break;
      case 2:
        page = const SavedCardsPage();
        break;
      case 3:
        page = const ReadCardPage();
        break;
      case 4:
        page = const WriteCardPage();
        break;
      case 5:
        page = const ToolsPage();
        break;
      case 6:
        page = const SettingsMainPage();
        break;
      case 7:
        page = const DebugPage();
        break;
      default:
        throw UnimplementedError('no widget for $selectedIndex');
    }

    try {
      WakelockPlus.toggle(enable: page is FlashingPage);
    } catch (_) {}

    return MaterialApp(
      title: 'Chameleon Ultra GUI', // App Name
      locale: widget.sharedPreferencesProvider.getLocale(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildIosTheme(Brightness.light,
              widget.sharedPreferencesProvider.getThemeColor())
          .useCustomSystemFont(Brightness.light),
      darkTheme: buildIosTheme(
              Brightness.dark, widget.sharedPreferencesProvider.getThemeColor())
          .useCustomSystemFont(Brightness.dark),
      themeMode: widget.sharedPreferencesProvider.getTheme(), // Dark Theme
      home: LayoutBuilder(// Build Page
          builder: (context, constraints) {
        final showNav =
            !appState.connector!.isDFU || !appState.connector!.connected;
        final isPhone = constraints.maxWidth < 600;

        if (isPhone) {
          // Phones: Android/iOS-style bottom tab bar instead of a side rail,
          // so the page gets the full width of the screen.
          return Scaffold(
            body: page,
            bottomNavigationBar: showNav
                ? _buildBottomNavigation(context, appState)
                : const SafeArea(child: BottomProgressBar()),
          );
        }

        return SafeArea(
          left: false,
          right: false,
          top: false,
          bottom: true,
          child: Scaffold(
              body: Row(
                children: [
                  showNav
                      ? (_navHidden
                          ? _collapsedNavStrip(context)
                          : SafeArea(
                              child: NavigationRail(
                                key: appState.navigationRailKey,
                                // Sidebar
                                leading: IconButton(
                                  icon: const Icon(Icons.menu_open),
                                  tooltip: AppLocalizations.of(context)!.close,
                                  onPressed: () =>
                                      setState(() => _navHidden = true),
                                ),
                                extended: appState.sharedPreferencesProvider
                                    .getSideBarExpanded(),
                                destinations:
                                    _railDestinations(context, appState),
                                selectedIndex: selectedIndex,
                                onDestinationSelected: (value) {
                                  setState(() {
                                    selectedIndex = value;
                                  });
                                },
                              ),
                            ))
                      : const SizedBox(),
                  Expanded(
                    child: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: page,
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: const BottomProgressBar()),
        );
      }),
    );
  }

  List<NavigationRailDestination> _railDestinations(
      BuildContext context, ChameleonGUIState appState) {
    final localizations = AppLocalizations.of(context)!;
    final connected = appState.connector!.connected;
    return [
      NavigationRailDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home),
        label: Text(localizations.home),
      ),
      NavigationRailDestination(
        disabled: !connected,
        icon: const Icon(Icons.widgets_outlined),
        selectedIcon: const Icon(Icons.widgets),
        label: Text(localizations.slot_manager),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.style_outlined),
        selectedIcon: const Icon(Icons.style),
        label: Text(localizations.saved_cards),
      ),
      NavigationRailDestination(
        disabled: !connected,
        icon: const Icon(Icons.sensors),
        label: Text(localizations.read_card),
      ),
      NavigationRailDestination(
        disabled: !connected,
        icon: const Icon(Icons.system_update_alt),
        label: Text(localizations.write_card),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.handyman_outlined),
        selectedIcon: const Icon(Icons.handyman),
        label: Text(localizations.tools),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings),
        label: Text(localizations.settings),
      ),
      if (appState.devMode)
        NavigationRailDestination(
          icon: const Icon(Icons.bug_report_outlined),
          selectedIcon: const Icon(Icons.bug_report),
          label: Text(localizations.debug),
        ),
    ];
  }

  // Pages that get a dedicated tab on phones; everything else lives behind
  // the "More" tab.
  static const List<int> _phonePrimaryPages = [0, 1, 2, 3];
  static const int _moreTabIndex = 4;

  Widget _buildBottomNavigation(
      BuildContext context, ChameleonGUIState appState) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final connected = appState.connector!.connected;
    final moreSelected = !_phonePrimaryPages.contains(selectedIndex);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const BottomProgressBar(),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: theme.dividerColor, width: 0.5),
            ),
          ),
          child: NavigationBar(
            selectedIndex: moreSelected ? _moreTabIndex : selectedIndex,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (value) {
              if (value == _moreTabIndex) {
                _showMoreSheet(context, appState);
                return;
              }
              setState(() => selectedIndex = value);
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home),
                label: localizations.home,
              ),
              NavigationDestination(
                enabled: connected,
                icon: const Icon(Icons.widgets_outlined),
                selectedIcon: const Icon(Icons.widgets),
                label: localizations.slot_manager,
              ),
              NavigationDestination(
                icon: const Icon(Icons.style_outlined),
                selectedIcon: const Icon(Icons.style),
                label: localizations.saved_cards,
              ),
              NavigationDestination(
                enabled: connected,
                icon: const Icon(Icons.sensors),
                label: localizations.read_card,
              ),
              NavigationDestination(
                icon: const Icon(Icons.more_horiz),
                label: localizations.more,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showMoreSheet(BuildContext context, ChameleonGUIState appState) {
    final localizations = AppLocalizations.of(context)!;
    final connected = appState.connector!.connected;
    final accent = Theme.of(context).colorScheme.primary;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        Widget item(int index, IconData icon, String label,
            {bool enabled = true}) {
          final selected = selectedIndex == index;
          return ListTile(
            enabled: enabled,
            selected: selected,
            selectedColor: accent,
            leading: Icon(icon),
            title: Text(label),
            trailing: selected ? Icon(Icons.check, color: accent) : null,
            onTap: () {
              Navigator.pop(sheetContext);
              setState(() => selectedIndex = index);
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(4, Icons.system_update_alt, localizations.write_card,
                  enabled: connected),
              item(5, Icons.handyman_outlined, localizations.tools),
              item(6, Icons.settings_outlined, localizations.settings),
              if (appState.devMode)
                item(7, Icons.bug_report_outlined, localizations.debug),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class BottomProgressBar extends StatelessWidget {
  const BottomProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    return (appState.connector!.connected && appState.connector!.isDFU)
        ? LinearProgressIndicator(
            value: appState.progress,
            backgroundColor: Colors.grey[300],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          )
        : const SizedBox();
  }
}
