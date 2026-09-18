import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leafy/main.dart';
import 'package:leafy/ads/ads_controller.dart';
import 'package:leafy/state/leafy_controller.dart';

void main() {
  testWidgets('guest adds and reviews a word without Firebase or ads', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = LeafyController(prefs);
    await c.start();
    await tester.pumpWidget(LeafyApp(controller: c, ads: AdsController()));
    await tester.pumpAndSettle();
    expect(find.text('Leafy'), findsOneWidget);
    await tester.tap(find.text('단어 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'leaf');
    await tester.enterText(find.byType(TextFormField).at(1), '잎');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('leaf'), findsOneWidget);
    expect(c.book.words.single.meaning, '잎');
    await tester.tap(find.text('학습'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('플래시카드'));
    await tester.tap(find.text('플래시카드'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('정답 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기억해요'));
    await tester.pumpAndSettle();
    expect(c.book.reviews.single['correct'], true);
    expect(c.book.words.single.level, 1);
    expect(tester.takeException(), isNull);
  });
}
