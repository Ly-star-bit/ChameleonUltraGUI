import 'dart:async';
import 'dart:io';

import 'package:chameleonultragui/helpers/feedback.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';

/// Watches the device GPS position and, when the user enters the radius of a
/// saved [LocationSlot], activates the matching slot on the Chameleon.
///
/// The monitor only takes action while [isConnected] returns true, so it is
/// safe to keep running even when the device is unplugged. All slot changes go
/// through [activateSlot] which the owner wires to the live communicator.
class LocationSlotMonitor {
  final SharedPreferencesProvider prefs;
  final Future<void> Function(int slot) activateSlot;
  final bool Function() isConnected;
  final Logger? log;

  StreamSubscription<Position>? _subscription;
  int? _lastActivatedSlot;

  /// Text shown on the Android foreground-service notification that keeps the
  /// app alive in the background. Set before [start] to localize it.
  String notificationTitle = "Chameleon Ultra GUI";
  String notificationText = "Auto-switching cards by location";

  /// Name of the location we are currently inside of, or null when outside all
  /// geofences. Exposed so the UI can show live status.
  String? activeLocationName;

  bool get running => _subscription != null;

  LocationSlotMonitor({
    required this.prefs,
    required this.activateSlot,
    required this.isConnected,
    this.log,
  });

  /// Ensures location services are on and permission is granted, requesting it
  /// if needed. Returns false when the feature cannot run at all.
  ///
  /// A "while in use" grant is enough to run while the app is foregrounded;
  /// [hasBackgroundPermission] reports whether background switching will work.
  Future<bool> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Whether the OS granted background ("Always" / "Allow all the time")
  /// location access, required to keep switching while the app is not visible.
  Future<bool> hasBackgroundPermission() async {
    return await Geolocator.checkPermission() == LocationPermission.always;
  }

  /// Tries to escalate to background ("Always") permission. On Android 11+ and
  /// iOS the OS routes this through a second prompt or the settings screen, so
  /// the result may only take effect after the user returns to the app.
  Future<bool> requestBackgroundPermission() async {
    await ensurePermission();
    final permission = await Geolocator.requestPermission();
    return permission == LocationPermission.always;
  }

  LocationSettings _buildLocationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
        // Runs the location stream inside a foreground service so Android does
        // not kill the process (and our BLE connection) while backgrounded.
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationTitle: notificationTitle,
          notificationText: notificationText,
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }

    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
        pauseLocationUpdatesAutomatically: false,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 15,
    );
  }

  /// Starts watching the position stream. Idempotent. Returns false when
  /// permission was denied or location services are off.
  Future<bool> start({String? notificationTitle, String? notificationText}) async {
    if (notificationTitle != null) {
      this.notificationTitle = notificationTitle;
    }
    if (notificationText != null) {
      this.notificationText = notificationText;
    }

    if (running) {
      return true;
    }

    if (!await ensurePermission()) {
      log?.w("Location slot monitor: permission or service unavailable");
      return false;
    }

    // Re-evaluate the current position as soon as we start so a slot switch
    // happens immediately instead of after the next movement.
    _lastActivatedSlot = null;

    _subscription = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(),
    ).listen(
      _onPosition,
      onError: (dynamic error) {
        log?.e("Location slot monitor stream error: $error");
      },
    );

    log?.i("Location slot monitor started");
    return true;
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _lastActivatedSlot = null;
    activeLocationName = null;
    log?.i("Location slot monitor stopped");
  }

  // --- Time based switching (independent of GPS/permission) ---

  Timer? _scheduleTimer;
  int? _lastScheduleSlot;

  bool get scheduleRunning => _scheduleTimer != null;

  /// Starts a periodic check that activates a slot while a [ScheduleSlot]
  /// window is active. Idempotent. Needs no location permission.
  void startSchedule() {
    if (scheduleRunning) {
      return;
    }
    _lastScheduleSlot = null;
    _scheduleTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _evaluateSchedule());
    _evaluateSchedule();
    log?.i("Schedule slot monitor started");
  }

  void stopSchedule() {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    _lastScheduleSlot = null;
    log?.i("Schedule slot monitor stopped");
  }

  Future<void> _evaluateSchedule() async {
    if (!isConnected()) {
      return;
    }

    final now = DateTime.now();
    ScheduleSlot? matched;
    for (final schedule in prefs.getScheduleSlots()) {
      if (schedule.matches(now)) {
        matched = schedule;
        break;
      }
    }

    if (matched == null) {
      _lastScheduleSlot = null;
      return;
    }

    if (_lastScheduleSlot == matched.slot) {
      return;
    }

    try {
      await activateSlot(matched.slot);
      _lastScheduleSlot = matched.slot;
      AppFeedback.light();
      log?.i(
          "Schedule slot monitor: activated slot ${matched.slot + 1} for ${matched.name}");
    } catch (error) {
      log?.e("Schedule slot monitor: failed to activate slot: $error");
    }
  }

  Future<void> _onPosition(Position position) async {
    if (!isConnected()) {
      return;
    }

    final locations =
        prefs.getLocationSlots().where((location) => location.enabled).toList();

    LocationSlot? matched;
    double? bestDistance;
    for (final location in locations) {
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        location.latitude,
        location.longitude,
      );

      if (distance <= location.radius &&
          (bestDistance == null || distance < bestDistance)) {
        bestDistance = distance;
        matched = location;
      }
    }

    if (matched == null) {
      activeLocationName = null;
      return;
    }

    activeLocationName = matched.name;

    if (_lastActivatedSlot == matched.slot) {
      return;
    }

    try {
      await activateSlot(matched.slot);
      _lastActivatedSlot = matched.slot;
      AppFeedback.light();
      log?.i(
          "Location slot monitor: activated slot ${matched.slot + 1} for ${matched.name}");
    } catch (error) {
      log?.e("Location slot monitor: failed to activate slot: $error");
    }
  }
}
