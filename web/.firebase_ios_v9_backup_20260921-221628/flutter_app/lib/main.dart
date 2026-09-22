import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ads/ads_controller.dart';
import 'config/firebase_config.dart';
import 'state/leafy_controller.dart';
import 'ui/app_theme.dart';
import 'ui/home_screen.dart';

Future<bool> _initializeFirebase() async {
  if (kIsWeb) {
    if (!FirebaseConfig.configured) return false;
    await Firebase.initializeApp(options: FirebaseConfig.options);
    return true;
  }

  try {
    await Firebase.initializeApp();
    return true;
  } catch (_) {
    if (!FirebaseConfig.configured) return false;
    await Firebase.initializeApp(options: FirebaseConfig.options);
    return true;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final preferences = await SharedPreferences.getInstance();
    final firebaseReady = await _initializeFirebase();

    final controller = LeafyController(
      preferences,
      auth: firebaseReady ? FirebaseAuth.instance : null,
      firestore: firebaseReady ? FirebaseFirestore.instance : null,
    );
    final ads = AdsController();

    runApp(LeafyApp(controller: controller, ads: ads));
    unawaited(controller.start());
    unawaited(
      ads.start().catchError((Object error) {
        ads.ready = false;
        debugPrint('광고 초기화를 완료하지 못했습니다.');
      }),
    );
  } catch (error) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Leafy를 시작하지 못했습니다.\n\n$error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LeafyApp extends StatelessWidget {
  const LeafyApp({
    super.key,
    required this.controller,
    required this.ads,
  });

  final LeafyController controller;
  final AdsController ads;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Leafy',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: LeafyTheme.light(),
        home: HomeScreen(controller: controller, ads: ads),
      );
}
