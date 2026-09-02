import 'dart:io';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/gui/menu/tools/dictionary_download.dart';
import 'package:chameleonultragui/gui/menu/tools/hf_sniffing.dart';
import 'package:chameleonultragui/gui/menu/tools/lf_sniffing.dart';
import 'package:chameleonultragui/gui/menu/tools/location_slots.dart';
import 'package:chameleonultragui/gui/menu/tools/schedule_slots.dart';
import 'package:chameleonultragui/gui/menu/tools/smart_copy.dart';
import 'package:chameleonultragui/gui/menu/tools/troubleshooter.dart';
import 'package:chameleonultragui/gui/menu/tools/t55xx_password_cleaner.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:provider/provider.dart';

class ToolItem {
  final String name;
  final String description;
  final IconData icon;
  final bool isDeviceRequired;
  final bool showWipBadge;
  final Widget? onPressed;

  ToolItem({
    required this.name,
    required this.description,
    required this.icon,
    this.isDeviceRequired = false,
    this.showWipBadge = false,
    this.onPressed,
  });
}

class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  ToolsPageState createState() => ToolsPageState();
}

class ToolsPageState extends State<ToolsPage> {
  @override
  Widget build(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    var localizations = AppLocalizations.of(context)!;

    List<ToolItem> tools = [
      ToolItem(
          name: localizations.smart_copy,
          description: localizations.smart_copy_description,
          icon: Icons.copy_all,
          onPressed: const SmartCopyMenu(),
          isDeviceRequired: true),
      ToolItem(
          name: localizations.dictionary_download,
          description: localizations.dictionary_download_description,
          icon: Icons.key,
          onPressed: const DictionaryDownloadMenu()),
      ToolItem(
          name: localizations.t55xx_password_cleaner,
          description: localizations.t55xx_password_cleaner_description,
          icon: Icons.password,
          onPressed: const T55XXPasswordCleanerMenu(),
          isDeviceRequired: true),
      ToolItem(
          name: localizations.lf_sniffing,
          description: localizations.lf_sniffing_description,
          icon: Icons.graphic_eq,
          onPressed: const LfSniffingMenu()),
      ToolItem(
          name: localizations.hf_sniffing,
          description: localizations.hf_sniffing_description,
          icon: Icons.radar,
          onPressed: const HfSniffingMenu()),
      ToolItem(
          name: localizations.mifare_classic_gen4,
          description: localizations.mifare_classic_gen4_description,
          icon: Icons.settings,
          isDeviceRequired: true),
      if (Platform.isAndroid || Platform.isIOS)
        ToolItem(
            name: localizations.location_slots,
            description: localizations.location_slots_description,
            icon: Icons.my_location,
            onPressed: const LocationSlotsMenu()),
      ToolItem(
          name: localizations.schedule_slots,
          description: localizations.schedule_slots_description,
          icon: Icons.schedule,
          onPressed: const ScheduleSlotsMenu()),
      ToolItem(
          name: localizations.troubleshooter,
          description: localizations.troubleshooter_description,
          icon: Icons.help_center,
          onPressed: const TroubleshooterMenu()),
    ];

    final width = MediaQuery.of(context).size.width;
    final connected = appState.connector!.connected;

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.tools),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: AlignedGridView.count(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            crossAxisCount: width >= 700 ? 2 : 1,
            crossAxisSpacing: 12,
            mainAxisSpacing: 10,
            itemCount: tools.length,
            itemBuilder: (BuildContext context, int index) {
              final tool = tools[index];
              final wip = tool.showWipBadge || tool.onPressed == null;
              final needsDevice = tool.isDeviceRequired && !connected;
              final enabled = tool.onPressed != null && !needsDevice;

              return _ToolCard(
                tool: tool,
                enabled: enabled,
                badges: [
                  if (wip)
                    _Badge(label: localizations.wip, color: Colors.orange),
                  if (needsDevice)
                    _Badge(
                      label: localizations.device_required,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                ],
                onTap: enabled
                    ? () {
                        showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return tool.onPressed!;
                            });
                      }
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final ToolItem tool;
  final bool enabled;
  final List<Widget> badges;
  final VoidCallback? onTap;

  const _ToolCard({
    required this.tool,
    required this.enabled,
    required this.badges,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(tool.icon, color: accent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tool.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tool.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                      if (badges.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 4, children: badges),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
