import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ads/ads_controller.dart';
import 'config/firebase_config.dart';
import 'state/leafy_controller.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    if (FirebaseConfig.configured)
      await Firebase.initializeApp(options: FirebaseConfig.options);
    final controller = LeafyController(
      prefs,
      auth: FirebaseConfig.configured ? FirebaseAuth.instance : null,
      firestore: FirebaseConfig.configured ? FirebaseFirestore.instance : null,
    );
    final ads = AdsController();
    runApp(LeafyApp(controller: controller, ads: ads));
    unawaited(controller.start());
    unawaited(ads.start().catchError((Object error) {
      ads.ready = false;
      debugPrint('광고 초기화를 완료하지 못했습니다.');
    }));
  } catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Leafy를 시작하지 못했습니다. 설정을 확인하고 다시 실행해주세요.\n$error'),
            ),
          ),
        ),
      ),
    );
  }
}

class LeafyApp extends StatelessWidget {
  const LeafyApp({super.key, required this.controller, required this.ads});
  final LeafyController controller;
  final AdsController ads;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Leafy',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff386b50)),
      scaffoldBackgroundColor: const Color(0xfff7f8f3),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.symmetric(vertical: 6),
      ),
    ),
    home: HomeScreen(controller: controller, ads: ads),
  );
}
