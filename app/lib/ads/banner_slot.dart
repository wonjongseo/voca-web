import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads_controller.dart';

class _BannerSlotController extends GetxController {
  _BannerSlotController(this.ads);

  final AdsController ads;
  BannerAd? ad;
  bool loaded = false;

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  void _load() {
    if (!ads.ready || !ads.supported || ads.bannerId.isEmpty) return;

    ad = BannerAd(
      size: AdSize.banner,
      adUnitId: ads.bannerId,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          loaded = true;
          update();
        },
        onAdFailedToLoad: (failedAd, error) {
          failedAd.dispose();
          ad = null;
          loaded = false;
          update();
        },
      ),
      request: const AdRequest(),
    )..load();
  }

  @override
  void onClose() {
    ad?.dispose();
    ad = null;
    super.onClose();
  }
}

class BannerSlot extends StatelessWidget {
  const BannerSlot({super.key, required this.ads});

  final AdsController ads;

  @override
  Widget build(BuildContext context) => GetBuilder<_BannerSlotController>(
        init: _BannerSlotController(ads),
        global: false,
        builder: (state) {
          final ad = state.ad;
          if (!state.loaded || ad == null) return const SizedBox.shrink();

          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '광고',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
                SizedBox(
                  width: ad.size.width.toDouble(),
                  height: ad.size.height.toDouble(),
                  child: AdWidget(ad: ad),
                ),
              ],
            ),
          );
        },
      );
}
