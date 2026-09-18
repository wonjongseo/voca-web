import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ads_controller.dart';

/// Mobile only. Web advertisements belong in the host HTML/React AdSense slot.
class BannerSlot extends StatefulWidget {
  const BannerSlot({super.key, required this.ads});
  final AdsController ads;
  @override
  State<BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<BannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;
  @override
  void initState() {
    super.initState();
    if (!widget.ads.ready || !widget.ads.supported) return;
    _ad = BannerAd(
      size: AdSize.banner,
      adUnitId: widget.ads.bannerId,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
        },
      ),
      request: const AdRequest(),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_loaded || _ad == null
      ? const SizedBox.shrink()
      : SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '광고',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
              SizedBox(
                width: _ad!.size.width.toDouble(),
                height: _ad!.size.height.toDouble(),
                child: AdWidget(ad: _ad!),
              ),
            ],
          ),
        );
}
