import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

String _formatMinutes(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return "$h:$m";
}

class ScheduleSlotsMenu extends StatefulWidget {
  const ScheduleSlotsMenu({super.key});

  @override
  ScheduleSlotsMenuState createState() => ScheduleSlotsMenuState();
}

class ScheduleSlotsMenuState extends State<ScheduleSlotsMenu> {
  late List<ScheduleSlot> schedules;
  late bool autoSwitchEnabled;

  @override
  void initState() {
    super.initState();
    final appState = context.read<ChameleonGUIState>();
    schedules = appState.sharedPreferencesProvider.getScheduleSlots();
    autoSwitchEnabled =
        appState.sharedPreferencesProvider.getScheduleSwitchEnabled();
  }

  void _persist() {
    context.read<ChameleonGUIState>().sharedPreferencesProvider
        .setScheduleSlots(schedules);
  }

  void _toggleAutoSwitch(bool value) {
    final appState = context.read<ChameleonGUIState>();
    appState.sharedPreferencesProvider.setScheduleSwitchEnabled(value);
    if (value) {
      appState.startScheduleMonitor();
    } else {
      appState.stopScheduleMonitor();
    }
    setState(() {
      autoSwitchEnabled = value;
    });
  }

  Future<void> _addOrEdit({ScheduleSlot? existing}) async {
    final result = await showDialog<ScheduleSlot>(
      context: context,
      builder: (context) => ScheduleSlotEditor(existing: existing),
    );
    if (result == null) {
      return;
    }
    setState(() {
      final index = schedules.indexWhere((s) => s.id == result.id);
      if (index >= 0) {
        schedules[index] = result;
      } else {
        schedules.add(result);
      }
    });
    _persist();
  }

  void _delete(ScheduleSlot schedule) {
    setState(() {
      schedules.removeWhere((s) => s.id == schedule.id);
    });
    _persist();
  }

  String _weekdayLabel(ScheduleSlot schedule, AppLocalizations localizations) {
    if (schedule.weekdays.isEmpty) {
      return localizations.every_day;
    }
    const names = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    final sorted = [...schedule.weekdays]..sort();
    return sorted.map((d) => names[d]).join(" ");
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.schedule_slots),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.schedule_slots_hint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(localizations.schedule_auto_switch),
                value: autoSwitchEnabled,
                onChanged: _toggleAutoSwitch,
              ),
              const Divider(),
              if (schedules.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(localizations.no_schedules),
                )
              else
                ...schedules.map(
                  (schedule) => Card(
                    child: ListTile(
                      leading: Icon(
                        schedule.enabled ? Icons.schedule : Icons.timer_off,
                        color: schedule.enabled
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      title: Text(schedule.name),
                      subtitle: Text(
                          "${_formatMinutes(schedule.startMinutes)}–${_formatMinutes(schedule.endMinutes)} · ${_weekdayLabel(schedule, localizations)} · ${localizations.slot} ${schedule.slot + 1}"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _addOrEdit(existing: schedule),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _delete(schedule),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: () => _addOrEdit(),
                  icon: const Icon(Icons.add_alarm),
                  label: Text(localizations.add_schedule),
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

class ScheduleSlotEditor extends StatefulWidget {
  final ScheduleSlot? existing;

  const ScheduleSlotEditor({super.key, this.existing});

  @override
  ScheduleSlotEditorState createState() => ScheduleSlotEditorState();
}

class ScheduleSlotEditorState extends State<ScheduleSlotEditor> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late int _startMinutes;
  late int _endMinutes;
  late List<int> _weekdays;
  int _slot = 0;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? "");
    _startMinutes = existing?.startMinutes ?? 8 * 60;
    _endMinutes = existing?.endMinutes ?? 18 * 60;
    _weekdays = [...(existing?.weekdays ?? <int>[])];
    _slot = existing?.slot ?? 0;
    _enabled = existing?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _startMinutes : _endMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    if (picked != null) {
      setState(() {
        final minutes = picked.hour * 60 + picked.minute;
        if (isStart) {
          _startMinutes = minutes;
        } else {
          _endMinutes = minutes;
        }
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      ScheduleSlot(
        id: widget.existing?.id,
        name: _nameController.text.trim(),
        startMinutes: _startMinutes,
        endMinutes: _endMinutes,
        weekdays: _weekdays,
        slot: _slot,
        enabled: _enabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    const weekdayNames = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

    return AlertDialog(
      title: Text(widget.existing == null
          ? localizations.add_schedule
          : localizations.edit_schedule),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: localizations.location_name,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? localizations.location_name
                    : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTime(true),
                      child: Text(
                          "${localizations.start_time}: ${_formatMinutes(_startMinutes)}"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickTime(false),
                      child: Text(
                          "${localizations.end_time}: ${_formatMinutes(_endMinutes)}"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(localizations.repeat_on,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: List.generate(7, (i) {
                  final day = i + 1; // 1=Mon .. 7=Sun
                  final selected = _weekdays.contains(day);
                  return FilterChip(
                    label: Text(weekdayNames[day]),
                    selected: selected,
                    onSelected: (value) {
                      setState(() {
                        if (value) {
                          _weekdays.add(day);
                        } else {
                          _weekdays.remove(day);
                        }
                      });
                    },
                  );
                }),
              ),
              Text(
                _weekdays.isEmpty ? localizations.every_day : "",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: _slot,
                decoration: InputDecoration(
                  labelText: localizations.select_slot,
                  border: const OutlineInputBorder(),
                ),
                items: List.generate(
                  8,
                  (index) => DropdownMenuItem(
                    value: index,
                    child: Text("${localizations.slot} ${index + 1}"),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _slot = value ?? 0;
                  });
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(localizations.enabled),
                value: _enabled,
                onChanged: (value) {
                  setState(() {
                    _enabled = value;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.cancel),
        ),
        ElevatedButton(
          onPressed: _save,
          child: Text(localizations.save),
        ),
      ],
    );
  }
}
