import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Explains where to physically place a card on the Chameleon so it can be
/// read: high frequency (13.56 MHz, IC cards) on the front, low frequency
/// (125 kHz, ID cards) on the back. Shown as a lightweight illustration so new
/// users are not left guessing why a read fails.
class AntennaGuideDialog extends StatelessWidget {
  const AntennaGuideDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.antenna_guide_title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              localizations.antenna_guide_intro,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _AntennaFace(
                  label: localizations.antenna_front_hf,
                  sublabel: "13.56 MHz",
                  icon: Icons.credit_card,
                  color: Colors.blue,
                ),
                _AntennaFace(
                  label: localizations.antenna_back_lf,
                  sublabel: "125 kHz",
                  icon: Icons.badge,
                  color: Colors.deepOrange,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _tip(context, Icons.touch_app, localizations.antenna_guide_tip1),
            _tip(context, Icons.center_focus_strong,
                localizations.antenna_guide_tip2),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.ok),
        ),
      ],
    );
  }

  Widget _tip(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _AntennaFace extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;

  const _AntennaFace({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 90,
          height: 120,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 8),
              Container(
                width: 60,
                height: 2,
                color: color.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(sublabel,
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
