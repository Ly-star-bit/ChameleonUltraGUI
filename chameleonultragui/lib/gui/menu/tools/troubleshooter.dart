import 'dart:io';

import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Plain-language "why isn't it working" helper. Shows the live connection
/// state and a checklist of common problems with concrete steps, instead of
/// leaving the user staring at a raw error code.
class TroubleshooterMenu extends StatelessWidget {
  const TroubleshooterMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final appState = context.watch<ChameleonGUIState>();
    final connected = appState.connector?.connected ?? false;
    final isDFU = appState.connector?.isDFU ?? false;

    final problems = <_Problem>[
      _Problem(
        icon: Icons.bluetooth_disabled,
        title: localizations.trouble_connect_title,
        steps: [
          localizations.trouble_connect_step_permission,
          if (Platform.isLinux) localizations.trouble_connect_step_modemmanager,
          if (Platform.isLinux) localizations.trouble_connect_step_dialout,
          localizations.trouble_connect_step_cable,
        ],
      ),
      _Problem(
        icon: Icons.sensors_off,
        title: localizations.trouble_read_title,
        steps: [
          localizations.trouble_read_step_antenna,
          localizations.trouble_read_step_still,
          localizations.trouble_read_step_encrypted,
        ],
      ),
      _Problem(
        icon: Icons.lock,
        title: localizations.trouble_encrypted_title,
        steps: [
          localizations.trouble_encrypted_step_dict,
          localizations.trouble_encrypted_step_recover,
        ],
      ),
      _Problem(
        icon: Icons.memory,
        title: localizations.trouble_dfu_title,
        steps: [
          localizations.trouble_dfu_step_flash,
          localizations.trouble_dfu_step_reboot,
        ],
      ),
      _Problem(
        icon: Icons.my_location,
        title: localizations.trouble_autoswitch_title,
        steps: [
          localizations.trouble_autoswitch_step_connected,
          localizations.trouble_autoswitch_step_background,
        ],
      ),
    ];

    return AlertDialog(
      title: Text(localizations.troubleshooter),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                color: (connected ? Colors.green : Colors.orange)
                    .withValues(alpha: 0.12),
                child: ListTile(
                  leading: Icon(
                    connected ? Icons.check_circle : Icons.error_outline,
                    color: connected ? Colors.green : Colors.orange,
                  ),
                  title: Text(connected
                      ? localizations.trouble_status_connected
                      : localizations.trouble_status_disconnected),
                  subtitle: connected
                      ? Text(
                          "${appState.connector?.portName ?? ''} · ${appState.connector?.connectionType.name ?? ''}${isDFU ? ' · DFU' : ''}")
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              ...problems.map(
                (problem) => Card(
                  child: ExpansionTile(
                    leading: Icon(problem.icon),
                    title: Text(problem.title),
                    childrenPadding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final step in problem.steps)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("• "),
                              Expanded(
                                child: Text(step,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.close),
        ),
      ],
    );
  }
}

class _Problem {
  final IconData icon;
  final String title;
  final List<String> steps;

  _Problem({required this.icon, required this.title, required this.steps});
}
