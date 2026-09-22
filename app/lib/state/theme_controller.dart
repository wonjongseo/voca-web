import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LeafyThemePreference {
  system,
  light,
  dark,
}

class ThemeController extends GetxController {
  ThemeController(this.preferences) {
    final stored = preferences.getString(_key);

    preference = switch (stored) {
      'light' => LeafyThemePreference.light,
      'dark' => LeafyThemePreference.dark,
      _ => LeafyThemePreference.system,
    };
  }

  static const _key = 'leafy-theme-mode-v1';

  final SharedPreferences preferences;

  LeafyThemePreference preference = LeafyThemePreference.system;

  ThemeMode get themeMode => switch (preference) {
        LeafyThemePreference.system => ThemeMode.system,
        LeafyThemePreference.light => ThemeMode.light,
        LeafyThemePreference.dark => ThemeMode.dark,
      };

  String get label => switch (preference) {
        LeafyThemePreference.system => '시스템 설정',
        LeafyThemePreference.light => '라이트 모드',
        LeafyThemePreference.dark => '다크 모드',
      };

  IconData get icon => switch (preference) {
        LeafyThemePreference.system => Icons.brightness_auto_rounded,
        LeafyThemePreference.light => Icons.light_mode_rounded,
        LeafyThemePreference.dark => Icons.dark_mode_rounded,
      };

  Future<void> setPreference(LeafyThemePreference value) async {
    preference = value;

    await preferences.setString(
      _key,
      switch (value) {
        LeafyThemePreference.system => 'system',
        LeafyThemePreference.light => 'light',
        LeafyThemePreference.dark => 'dark',
      },
    );

    Get.changeThemeMode(themeMode);
    update();
  }
}
