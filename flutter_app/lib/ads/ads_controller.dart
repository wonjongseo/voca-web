import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdsController extends ChangeNotifier {
  static const enabled = bool.fromEnvironment(
    'ADS_ENABLED',
    defaultValue: false,
  );
  static const production = bool.fromEnvironment(
    'ADS_PRODUCTION',
    defaultValue: false,
  );
  bool ready = false;
  bool privacyRequired = false;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  String get bannerId {
    if (production) {
      return defaultTargetPlatform == TargetPlatform.android
          ? const String.fromEnvironment('ADMOB_ANDROID_BANNER_ID')
          : const String.fromEnvironment('ADMOB_IOS_BANNER_ID');
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? 'ca-app-pub-3940256099942544/6300978111'
        : 'ca-app-pub-3940256099942544/2934735716';
  }

  Future<void> start() async {
    if (!enabled || !supported || bannerId.isEmpty) return;
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (!done.isCompleted) done.complete();
        });
      },
      (error) {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
    await _refresh();
  }

  Future<void> _refresh() async {
    privacyRequired =
        await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
    ready = await ConsentInformation.instance.canRequestAds();
    if (ready) await MobileAds.instance.initialize();
    notifyListeners();
  }

  Future<void> privacyOptions() async {
    // Remove the current banner before a user changes consent.
    ready = false;
    notifyListeners();
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      done.complete();
    });
    await done.future;
    await _refresh();
  }
}
