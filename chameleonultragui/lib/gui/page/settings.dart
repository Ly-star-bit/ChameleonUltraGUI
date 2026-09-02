import 'package:chameleonultragui/gui/component/developer_list.dart';
import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/gui/component/ios_widgets.dart';
import 'package:chameleonultragui/helpers/colors.dart' as colors;
import 'package:chameleonultragui/gui/menu/dialogs/qr/settings.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/helpers/open_collective.dart';
import 'package:chameleonultragui/main.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:chameleonultragui/gui/component/qrcode_viewer.dart';
import 'package:crypto/crypto.dart';
import 'package:chameleonultragui/gui/menu/dialogs/qr/import.dart';
import 'package:chameleonultragui/gui/menu/pages/changelog_view.dart';
import 'package:flutter/services.dart' show rootBundle;

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

Future<String> loadLicense(String license) async {
  return await rootBundle.loadString('assets/licenses/$license.md');
}

class SettingsMainPage extends StatefulWidget {
  const SettingsMainPage({super.key});

  @override
  SettingsMainPageState createState() => SettingsMainPageState();
}

class SettingsMainPageState extends State<SettingsMainPage> {
  @override
  void initState() {
    super.initState();
  }

  Future<(String, List<Map<String, String>>, PackageInfo)>
      getFutureData() async {
    return (
      await fetchOCnames(),
      await fetchContributors(),
      await PackageInfo.fromPlatform()
    );
  }

  Future<String> fetchOCnames() async {
    final List<String> names = await fetchOpenCollectiveContributors();

    if (names.isEmpty && mounted) {
      return AppLocalizations.of(context)!.failed_to_fetch_oc_contributors;
    }

    String finalNames = "";
    for (String name in names) {
      finalNames += "$name, ";
    }
    return finalNames.substring(0, finalNames.length - 2);
  }

  Future<List<Map<String, String>>> fetchContributors() async {
    return await fetchGitHubContributors();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _exportSettings(ChameleonGUIState appState) async {
    var localizations = AppLocalizations.of(context)!;

    await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(localizations.choose_export_method),
        content: Text(localizations.choose_export_method_description),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () async {
              String string =
                  appState.sharedPreferencesProvider.dumpSettingsToJson();

              Map<String, int> settings = await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return const QRCodeSettings();
                      }) ??
                  {};

              if (settings.isEmpty) {
                return;
              }

              List<String> qrChunks =
                  splitStringIntoQrChunks(string, settings["splitSize"]!);

              // Generate Header Info
              Map<String, dynamic> headerData = {
                "Info": "Chameleon Ultra GUI Settings",
                "chunks": qrChunks.length,
                "sha256": sha256
                    .convert(const Utf8Encoder().convert(string))
                    .toString(),
              };
              qrChunks.insert(0, jsonEncode(headerData));

              if (context.mounted) {
                await showDialog(
                  context: context,
                  builder: (BuildContext context) => QrCodeViewer(
                      qrChunks: qrChunks,
                      errorCorrection: settings["errorCorrection"]!),
                );
              }

              appState.changesMade();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: Text(localizations.qr_code),
          ),
          TextButton(
            onPressed: () async {
              await FilePicker.saveFile(
                dialogTitle: '${localizations.output_file}:',
                fileName: 'ChameleonUltraGUISettings.json',
                bytes: const Utf8Encoder().convert(
                    appState.sharedPreferencesProvider.dumpSettingsToJson()),
              );
            },
            child: Text(localizations.json_file),
          ),
        ],
      ),
    );
  }

  Future<void> _importSettings(ChameleonGUIState appState) async {
    var localizations = AppLocalizations.of(context)!;

    await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(localizations.import_settings),
        content: Text(localizations.import_settings_description),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () async {
              if (!(Platform.isAndroid || Platform.isIOS)) {
                await showDialog(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    title: Text(localizations.error),
                    content: Text(
                        localizations.qr_code_import_not_supported_description),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(localizations.ok),
                      ),
                    ],
                  ),
                );
                return;
              }

              String? jsonData = await showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return const QrCodeImport();
                  });

              if (jsonData == null) {
                return;
              }
              appState.sharedPreferencesProvider
                  .restoreSettingsFromJson(jsonData);

              appState.changesMade();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: Text(localizations.qr_code),
          ),
          TextButton(
            onPressed: () async {
              PlatformFile? result = await FilePicker.pickFile();
              if (result != null) {
                File file = File(result.path!);
                var contents = await file.readAsBytes();
                var string = const Utf8Decoder().convert(contents);
                appState.sharedPreferencesProvider
                    .restoreSettingsFromJson(string);
                appState.changesMade();
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: Text(localizations.json_file),
          ),
        ],
      ),
    );
  }

  Future<void> _showAbout(ChameleonGUIState appState) async {
    var localizations = AppLocalizations.of(context)!;

    await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(localizations.about),
        content: Center(
          child: FutureBuilder(
            future: getFutureData(),
            builder: (BuildContext context, AsyncSnapshot snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: AdaptiveProgress());
              } else if (snapshot.hasError) {
                appState.connector!.performDisconnect();
                return ErrorPage(errorMessage: snapshot.error.toString());
              } else {
                final (names, contributors, packageInfo) = snapshot.data;
                return SingleChildScrollView(
                    child: Column(
                  children: [
                    const Text('Chameleon Ultra GUI',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(localizations.about_text),
                    const SizedBox(height: 10),
                    Text('${localizations.version}:'),
                    Text(
                        '${packageInfo.version} (Build ${packageInfo.buildNumber})',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text('${localizations.developed_by}:'),
                    const SizedBox(height: 10),
                    DeveloperList(avatars: developers),
                    const SizedBox(height: 10),
                    Text('${localizations.license}:'),
                    const Text('GNU General Public License v3.0',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    GestureDetector(
                        onTap: () async {
                          await launchUrl(Uri.parse(
                              'https://github.com/GameTec-live/ChameleonUltraGUI'));
                        },
                        child: const Text(
                            'https://github.com/GameTec-live/ChameleonUltraGUI')),
                    const SizedBox(height: 30),
                    GestureDetector(
                        onTap: () async {
                          await launchUrl(Uri.parse(
                              'https://opencollective.com/chameleon-ultra-gui'));
                        },
                        child: Text(localizations.thanks_for_support)),
                    const SizedBox(height: 10),
                    Text(names,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text('${localizations.code_contributors}:'),
                    const SizedBox(height: 10),
                    DeveloperList(avatars: contributors),
                    const SizedBox(height: 10),
                    Text(localizations.trademarks_mifare),
                    const SizedBox(height: 10),
                    Text(localizations.trademarks_em),
                    const SizedBox(height: 10),
                    Text(localizations.trademarks_hid),
                  ],
                ));
              }
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _showLicenses() async {
    Map<String, String> licenses = {
      'BSD-3-Clause': await loadLicense('BSD-3-Clause'),
      'GPL3': await loadLicense('GPL3'),
      'LGPL3': await loadLicense('LGPL3'),
      'MIT': await loadLicense('MIT')
    };

    // font.dart
    LicenseRegistry.addLicense(() => Stream<LicenseEntry>.value(
          LicenseEntryWithLineBreaks(
            <String>['chinese_font_library'],
            licenses['BSD-3-Clause']!,
          ),
        ));

    // ported hardnested to Windows + MSVC, separation from proxmark3 code
    LicenseRegistry.addLicense(() => Stream<LicenseEntry>.value(
          LicenseEntryWithLineBreaks(
            <String>['FlipperNestedRecovery'],
            licenses['LGPL3']!,
          ),
        ));

    LicenseRegistry.addLicense(() => Stream<LicenseEntry>.value(
          LicenseEntryWithLineBreaks(
            <String>['proxmark3'],
            licenses['GPL3']!,
          ),
        ));

    // hardnested tables uncompressor
    LicenseRegistry.addLicense(() => Stream<LicenseEntry>.value(
          LicenseEntryWithLineBreaks(
            <String>['minlzma'],
            licenses['MIT']!,
          ),
        ));

    if (mounted) {
      showLicensePage(context: context);
    }
  }

  /// Asks for confirmation, then flips a developer toggle.
  Future<void> _confirmToggle({
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) async {
    var localizations = AppLocalizations.of(context)!;

    await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () {
              onConfirm();
              Navigator.pop(context);
            },
            child: Text(localizations.ok),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Building blocks
  // ---------------------------------------------------------------------------

  /// Title on one line, a full-width segmented control underneath.
  Widget _segmentedRow<T>({
    required String title,
    required List<ButtonSegment<T>> segments,
    required T selected,
    required ValueChanged<T> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              segments: segments,
              selected: {selected},
              onSelectionChanged: (value) => onChanged(value.first),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool external = false,
  }) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Icon(external ? Icons.open_in_new : Icons.chevron_right,
          size: external ? 18 : 24, color: muted),
      onTap: onTap,
    );
  }

  Widget _colorPicker(ChameleonGUIState appState) {
    final selectedIndex =
        appState.sharedPreferencesProvider.getThemeColorIndex();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context)!.color_scheme,
              style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(8, (i) {
              final swatch = colors.getThemeColor(i);
              final selected = selectedIndex == i;
              return GestureDetector(
                onTap: () {
                  appState.sharedPreferencesProvider.setThemeColor(i);
                  appState.changesMade();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: swatch,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.watch<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;
    final prefs = appState.sharedPreferencesProvider;
    final isWide = MediaQuery.of(context).size.width >= 600;
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.settings),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              // ----------------------------------------------------- Appearance
              IosListSection(
                header: localizations.appearance,
                children: [
                  _segmentedRow<int>(
                    title: localizations.theme,
                    segments: [
                      ButtonSegment(
                          value: 0, label: Text(localizations.system)),
                      ButtonSegment(value: 1, label: Text(localizations.light)),
                      ButtonSegment(value: 2, label: Text(localizations.dark)),
                    ],
                    selected: prefs.getTheme().index,
                    onChanged: (index) {
                      prefs.setTheme(ThemeMode.values[index]);
                      appState.changesMade();
                    },
                  ),
                  _colorPicker(appState),
                  ListTile(
                    leading: const Icon(Icons.language),
                    title: Text(localizations.language),
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: prefs.getLocaleString(),
                        style: TextStyle(fontSize: 15, color: muted),
                        onChanged: (value) {
                          prefs.setLocale(Locale(value ?? 'en'));
                          appState.changesMade();
                        },
                        items: AppLocalizations.supportedLocales.map((locale) {
                          final localeLocalizations =
                              lookupAppLocalizations(locale);
                          return DropdownMenuItem(
                              value: locale.toLanguageTag(),
                              child: Text(localeLocalizations.language_name));
                        }).toList(),
                      ),
                    ),
                  ),
                  if (isWide)
                    _segmentedRow<int>(
                      title: localizations.sidebar_expansion,
                      segments: [
                        ButtonSegment(
                            value: 0, label: Text(localizations.expand)),
                        ButtonSegment(
                            value: 1, label: Text(localizations.auto)),
                        ButtonSegment(
                            value: 2, label: Text(localizations.retract)),
                      ],
                      selected: prefs.getSideBarExpandedIndex(),
                      onChanged: (index) {
                        if (index == 0) {
                          prefs.setSideBarExpanded(true);
                          prefs.setSideBarAutoExpansion(false);
                        } else if (index == 2) {
                          prefs.setSideBarExpanded(false);
                          prefs.setSideBarAutoExpansion(false);
                        } else {
                          prefs.setSideBarAutoExpansion(true);
                        }
                        prefs.setSideBarExpandedIndex(index);
                        appState.changesMade();

                        WidgetsBinding.instance.addPostFrameCallback(
                            (_) => updateNavigationRailWidth(context));
                      },
                    ),
                ],
              ),

              // ----------------------------------------------------- Connection
              IosListSection(
                header: localizations.connection,
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.radar),
                    title: Text(localizations.auto_scan_devices),
                    value: prefs.getAutoScanEnabled(),
                    onChanged: (value) {
                      prefs.setAutoScanEnabled(value);
                      appState.changesMade();
                    },
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.bolt),
                    title: Text(localizations.auto_connect_first_device),
                    value: prefs.getAutoConnectFirstFoundDevice(),
                    onChanged: (value) {
                      prefs.setAutoConnectFirstFoundDevice(value);
                      appState.changesMade();
                    },
                  ),
                ],
              ),

              // ----------------------------------------------------- General
              IosListSection(
                header: localizations.general,
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.delete_outline),
                    title: Text(localizations.confirm_deletions),
                    value: prefs.getConfirmDelete(),
                    onChanged: (value) {
                      prefs.setConfirmDelete(value);
                      appState.changesMade();
                    },
                  ),
                ],
              ),

              // ----------------------------------------------------- Backup
              IosListSection(
                header: localizations.backup_restore,
                children: [
                  _linkTile(
                    icon: Icons.upload_outlined,
                    title: localizations.export_settings,
                    onTap: () => _exportSettings(appState),
                  ),
                  _linkTile(
                    icon: Icons.download_outlined,
                    title: localizations.import_settings,
                    onTap: () => _importSettings(appState),
                  ),
                ],
              ),

              // ----------------------------------------------------- About
              IosListSection(
                header: localizations.about,
                children: [
                  _linkTile(
                    icon: Icons.info_outline,
                    title: localizations.about,
                    onTap: () => _showAbout(appState),
                  ),
                  _linkTile(
                    icon: Icons.history,
                    title: localizations.changelog,
                    onTap: () => showDialog<String>(
                      context: context,
                      builder: (BuildContext context) => const ChangelogView(),
                    ),
                  ),
                  _linkTile(
                    icon: Icons.description_outlined,
                    title: localizations.licenses,
                    onTap: _showLicenses,
                  ),
                  _linkTile(
                    icon: Icons.translate,
                    title: localizations.help_translate,
                    external: true,
                    onTap: () async {
                      await launchUrl(Uri.parse(
                          'https://crowdin.com/project/chameleonultragui'));
                    },
                  ),
                ],
              ),

              // ----------------------------------------------------- Developer
              IosListSection(
                header: localizations.developer,
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.smart_toy_outlined),
                    title: Text(localizations.emulate_device),
                    value: prefs.isEmulatedChameleon(),
                    onChanged: (value) => _confirmToggle(
                      title: localizations.emulate_device,
                      message: localizations.emulate_device_confirmation(
                          prefs.isEmulatedChameleon()
                              ? localizations.deactivate.toLowerCase()
                              : localizations.activate.toLowerCase()),
                      onConfirm: () {
                        prefs
                            .setEmulatedChameleon(!prefs.isEmulatedChameleon());
                        appState.connector = null;
                        appState.changesMade();
                      },
                    ),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.bug_report_outlined),
                    title: Text(localizations.debug_mode),
                    value: prefs.isDebugMode(),
                    onChanged: (value) => _confirmToggle(
                      title: localizations.debug_mode,
                      message: localizations.debug_mode_confirmation(
                          prefs.isDebugMode()
                              ? localizations.deactivate.toLowerCase()
                              : localizations.activate.toLowerCase()),
                      onConfirm: () {
                        prefs.setDebugMode(!prefs.isDebugMode());
                        appState.changesMade();
                      },
                    ),
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
