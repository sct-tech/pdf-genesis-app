import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ads seam for a future AdMob integration. Screens ask this service for a
/// banner; today it returns nothing, and Pro users never see ads.
abstract class AdsService {
  Future<void> initialize();

  /// A banner to place at [placement], or null when no ad should show.
  Widget? banner({required String placement, required bool isPro});
}

class NoAdsService implements AdsService {
  @override
  Future<void> initialize() async {}

  @override
  Widget? banner({required String placement, required bool isPro}) => null;
}

final adsProvider = Provider<AdsService>((ref) => NoAdsService());
