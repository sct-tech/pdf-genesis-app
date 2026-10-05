import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Analytics seam. Screens log through this interface; swap the provider for
/// a Firebase (or other) implementation without touching the callers.
abstract class AnalyticsService {
  void logEvent(String name, [Map<String, Object?> parameters = const {}]);

  void setUserId(String? userId);
}

class DebugAnalyticsService implements AnalyticsService {
  @override
  void logEvent(String name, [Map<String, Object?> parameters = const {}]) {
    if (kDebugMode) debugPrint('[analytics] $name $parameters');
  }

  @override
  void setUserId(String? userId) {}
}

final analyticsProvider = Provider<AnalyticsService>(
  (ref) => DebugAnalyticsService(),
);
