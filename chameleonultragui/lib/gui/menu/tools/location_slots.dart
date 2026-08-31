import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

class LocationSlotsMenu extends StatefulWidget {
  const LocationSlotsMenu({super.key});

  @override
  LocationSlotsMenuState createState() => LocationSlotsMenuState();
}

class LocationSlotsMenuState extends State<LocationSlotsMenu> {
  late List<LocationSlot> locations;
  late bool autoSwitchEnabled;
  bool backgroundGranted = true;

  @override
  void initState() {
    super.initState();
    final appState = context.read<ChameleonGUIState>();
    locations = appState.sharedPreferencesProvider.getLocationSlots();
    autoSwitchEnabled =
        appState.sharedPreferencesProvider.getLocationSwitchEnabled();
    if (autoSwitchEnabled) {
      _refreshBackgroundStatus();
    }
  }

  Future<void> _refreshBackgroundStatus() async {
    final appState = context.read<ChameleonGUIState>();
    final granted =
        await appState.ensureLocationMonitor().hasBackgroundPermission();
    if (mounted) {
      setState(() {
        backgroundGranted = granted;
      });
    }
  }

  Future<void> _requestBackground() async {
    final appState = context.read<ChameleonGUIState>();
    await appState.ensureLocationMonitor().requestBackgroundPermission();
    await _refreshBackgroundStatus();
  }

  void _persist() {
    final appState = context.read<ChameleonGUIState>();
    appState.sharedPreferencesProvider.setLocationSlots(locations);
  }

  Future<void> _toggleAutoSwitch(bool value) async {
    final appState = context.read<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;

    if (value) {
      final granted = await appState.ensureLocationMonitor().ensurePermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.location_permission_denied)),
          );
        }
        return;
      }
    }

    appState.sharedPreferencesProvider.setLocationSwitchEnabled(value);
    if (value) {
      await appState.startLocationMonitor(
        notificationTitle: localizations.location_slots,
        notificationText: localizations.location_running_notification,
      );
      await _refreshBackgroundStatus();
    } else {
      appState.stopLocationMonitor();
    }

    setState(() {
      autoSwitchEnabled = value;
    });
  }

  Future<void> _addOrEdit({LocationSlot? existing}) async {
    final result = await showDialog<LocationSlot>(
      context: context,
      builder: (context) => LocationSlotEditor(existing: existing),
    );

    if (result == null) {
      return;
    }

    setState(() {
      final index = locations.indexWhere((l) => l.id == result.id);
      if (index >= 0) {
        locations[index] = result;
      } else {
        locations.add(result);
      }
    });
    _persist();
  }

  void _delete(LocationSlot location) {
    setState(() {
      locations.removeWhere((l) => l.id == location.id);
    });
    _persist();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.location_slots),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                localizations.location_slots_hint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(localizations.location_auto_switch),
                value: autoSwitchEnabled,
                onChanged: (value) => _toggleAutoSwitch(value),
              ),
              if (autoSwitchEnabled && !backgroundGranted)
                Card(
                  color: Colors.orange.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber,
                                color: Colors.orange, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                localizations.location_background_hint,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _requestBackground,
                            child:
                                Text(localizations.grant_background_permission),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Divider(),
              if (locations.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    localizations.no_locations,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                ...locations.map(
                  (location) => Card(
                    child: ListTile(
                      leading: Icon(
                        location.enabled
                            ? Icons.location_on
                            : Icons.location_off,
                        color: location.enabled
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      title: Text(location.name),
                      subtitle: Text(
                          "${localizations.slot} ${location.slot + 1} · ${location.radius.round()} m"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _addOrEdit(existing: location),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _delete(location),
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
                  icon: const Icon(Icons.add_location_alt),
                  label: Text(localizations.add_location),
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

class LocationSlotEditor extends StatefulWidget {
  final LocationSlot? existing;

  const LocationSlotEditor({super.key, this.existing});

  @override
  LocationSlotEditorState createState() => LocationSlotEditorState();
}

class LocationSlotEditorState extends State<LocationSlotEditor> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _radiusController;
  double? _latitude;
  double? _longitude;
  int _slot = 0;
  bool _enabled = true;
  bool _fetchingLocation = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? "");
    _radiusController =
        TextEditingController(text: (existing?.radius ?? 150).round().toString());
    _latitude = existing?.latitude;
    _longitude = existing?.longitude;
    _slot = existing?.slot ?? 0;
    _enabled = existing?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    final appState = context.read<ChameleonGUIState>();
    final localizations = AppLocalizations.of(context)!;

    setState(() {
      _fetchingLocation = true;
    });

    try {
      final granted = await appState.ensureLocationMonitor().ensurePermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.location_permission_denied)),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.location_permission_denied)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _fetchingLocation = false;
        });
      }
    }
  }

  void _save() {
    final localizations = AppLocalizations.of(context)!;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(localizations.coordinates_not_set)),
      );
      return;
    }

    final radius = double.tryParse(_radiusController.text) ?? 150;

    Navigator.of(context).pop(
      LocationSlot(
        id: widget.existing?.id,
        name: _nameController.text.trim(),
        latitude: _latitude!,
        longitude: _longitude!,
        radius: radius,
        slot: _slot,
        enabled: _enabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final hasCoordinates = _latitude != null && _longitude != null;

    return AlertDialog(
      title: Text(widget.existing == null
          ? localizations.add_location
          : localizations.edit_location),
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
              OutlinedButton.icon(
                onPressed: _fetchingLocation ? null : _useCurrentLocation,
                icon: _fetchingLocation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(localizations.use_current_location),
              ),
              const SizedBox(height: 8),
              Text(
                hasCoordinates
                    ? "${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}"
                    : localizations.coordinates_not_set,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _radiusController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: localizations.radius_meters,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final parsed = double.tryParse(value ?? "");
                  if (parsed == null || parsed <= 0) {
                    return localizations.radius_meters;
                  }
                  return null;
                },
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
