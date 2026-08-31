import 'package:flutter/services.dart';

/// Central place for tactile feedback so success/failure/switch events feel
/// consistent across the app (similar to the tap you feel at a payment gate).
///
/// Uses the platform [HapticFeedback] API which is a no-op on devices without a
/// vibration motor (desktops), so callers never need to guard by platform.
class AppFeedback {
  /// A card was read, a slot activated, or a connection established.
  static void success() {
    HapticFeedback.mediumImpact();
  }

  /// A light confirmation, e.g. an automatic slot switch in the background.
  static void light() {
    HapticFeedback.selectionClick();
  }

  /// Something went wrong: read failed, disconnected, write error.
  static void error() {
    HapticFeedback.heavyImpact();
  }
}
