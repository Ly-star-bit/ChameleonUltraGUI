import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/feedback.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';

/// Eight tappable slot pills. The active slot is filled with the accent
/// colour, slots that hold a card are tinted, empty slots are outlined.
/// Tapping a pill activates that slot on the device.
class SlotChanger extends StatefulWidget {
  final VoidCallback? onChanged;

  const SlotChanger({super.key, this.onChanged});

  @override
  SlotChangerState createState() => SlotChangerState();
}

class SlotChangerState extends State<SlotChanger> {
  int selectedSlot = 0; // zero-based
  List<bool> usedSlots = List.filled(8, false);
  Future<void>? _load;
  bool _switching = false;

  Future<void> _fetch() async {
    var appState = context.read<ChameleonGUIState>();
    List<SlotTypes> types = [];

    try {
      types = await appState.communicator!.getSlotTagTypes();
    } catch (_) {
      types = [];
    }

    try {
      selectedSlot = await appState.communicator!.getActiveSlot();
    } catch (_) {
      selectedSlot = 0;
    }

    usedSlots =
        List.generate(8, (i) => i < types.length && types[i].notMatch());
  }

  Future<void> _activate(int index) async {
    if (_switching || index == selectedSlot) {
      return;
    }

    var appState = context.read<ChameleonGUIState>();
    setState(() => _switching = true);

    try {
      await appState.communicator!.activateSlot(index);
      selectedSlot = index;
      AppFeedback.light();
    } catch (e) {
      appState.log?.e(e);
    }

    if (mounted) {
      setState(() => _switching = false);
    }

    appState.changesMade();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    _load ??= _fetch();

    return FutureBuilder<void>(
        future: _load,
        builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
          if (snapshot.hasError) {
            appState.connector!.performDisconnect();
            return ErrorPage(errorMessage: snapshot.error.toString());
          }

          final loading = snapshot.connectionState != ConnectionState.done;

          return Row(
            children: [
              for (int i = 0; i < 8; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _SlotPill(
                      index: i,
                      active: !loading && i == selectedSlot,
                      used: !loading && usedSlots[i],
                      onTap:
                          (loading || _switching) ? null : () => _activate(i),
                    ),
                  ),
                ),
            ],
          );
        });
  }
}

class _SlotPill extends StatelessWidget {
  final int index;
  final bool active;
  final bool used;
  final VoidCallback? onTap;

  const _SlotPill({
    required this.index,
    required this.active,
    required this.used,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.4);

    final Color background;
    final Color foreground;
    final BoxBorder? border;

    if (active) {
      background = accent;
      foreground = Colors.white;
      border = null;
    } else if (used) {
      background = accent.withValues(alpha: 0.14);
      foreground = accent;
      border = null;
    } else {
      background = Colors.transparent;
      foreground = muted;
      border = Border.all(color: theme.dividerColor, width: 1);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      height: 44,
      decoration: BoxDecoration(
        color: background,
        border: border,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Center(
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
