import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:leafy/data/notebook_repository.dart';
import 'package:leafy/domain/vocabulary.dart';
import 'package:leafy/state/leafy_controller.dart';

void main() {
  test(
    'web schema and extended fields survive local storage and editing',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = GuestRepository(prefs);
      await repo.load();
      final word = VocabWord.create('grow', '자라다').copy({
        'examples': [
          {'text': 'Plants grow.', 'translation': '식물이 자란다.'},
        ],
        'meaningEntries': ['자라다'],
        'synonymEntries': ['develop'],
      });
      await repo.putWord(word);
      await repo.setCategories(['TOEIC']);
      final reloaded = await GuestRepository(prefs).load();
      expect(reloaded.words.single.toJson(), word.toJson());
      expect(reloaded.categories, ['TOEIC']);
      final raw = jsonDecode(prefs.getString(guestStorageKey)!);
      expect(raw['version'], 1);
      await repo.deleteWord(word.id);
      expect((await GuestRepository(prefs).load()).words, isEmpty);
    },
  );
  test(
    'review schedule matches web intervals and resets incorrect answers',
    () {
      final now = DateTime(2026, 9, 18);
      var word = VocabWord.create('grow', '자라다');
      for (final days in [1, 3, 7, 14, 30, 60, 60]) {
        word = word.schedule(true, now);
        expect(word.due, now.add(Duration(days: days)).millisecondsSinceEpoch);
      }
      word = word.schedule(false, now);
      expect(word.level, 0);
      expect(
        word.due,
        now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
      );
    },
  );
  test('corrupt guest data is preserved and never overwritten', () async {
    SharedPreferences.setMockInitialValues({guestStorageKey: '{broken'});
    final prefs = await SharedPreferences.getInstance();
    final c = LeafyController(prefs);
    await c.start();
    expect(c.loaded, isFalse);
    expect(c.error, isNotNull);
    await expectLater(
      c.save(VocabWord.create('grow', '자라다')),
      throwsStateError,
    );
    expect(prefs.getString(guestStorageKey), '{broken');
    c.dispose();
  });
  test('guest review persists word progress and history together', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = LeafyController(prefs);
    await c.start();
    final word = VocabWord.create('leaf', '잎');
    await c.save(word);
    await c.grade(word, false);
    expect(c.wrongIds, contains(word.id));
    final restored = await GuestRepository(prefs).load();
    expect(restored.reviews.single['correct'], false);
    expect(restored.words.single.level, 0);
    c.dispose();
  });
}
