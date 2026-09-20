import 'package:uuid/uuid.dart';

const guestStorageKey = 'leafy-guest-v1';
String dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Keep the original web fields, including optional arrays, losslessly.
class VocabWord {
  VocabWord(Map<String, dynamic> json) : data = Map.unmodifiable(json);
  final Map<String, dynamic> data;
  factory VocabWord.create(String word, String meaning) => VocabWord({
    'id': const Uuid().v4(),
    'word': word,
    'meaning': meaning,
    'example': '',
    'translation': '',
    'synonyms': '',
    'memo': '',
    'category': '',
    'favorite': false,
    'level': 0,
    'due': 0,
    'created': DateTime.now().millisecondsSinceEpoch,
  });
  String get id => data['id'] as String;
  String get word => data['word'] as String;
  String get meaning => data['meaning'] as String;
  String text(String key) => data[key] as String? ?? '';
  bool get favorite => data['favorite'] == true;
  int get level => (data['level'] as num? ?? 0).toInt();
  int get due => (data['due'] as num? ?? 0).toInt();
  List<String> get meanings =>
      (data['meaningEntries'] as List?)?.cast<String>() ?? [meaning];
  VocabWord copy(Map<String, dynamic> changes) =>
      VocabWord({...data, ...changes});
  Map<String, dynamic> toJson() => Map.of(data)
    ..remove('updatedAt')
    ..remove('updatedBy');
  VocabWord schedule(bool correct, DateTime now) {
    final next = correct ? (level + 1).clamp(0, 6) : 0;
    final duration = correct
        ? Duration(days: [0, 1, 3, 7, 14, 30, 60][next])
        : const Duration(minutes: 10);
    return copy({
      'level': next,
      'due': now.add(duration).millisecondsSinceEpoch,
    });
  }
}

class Notebook {
  const Notebook({
    this.words = const [],
    this.reviews = const [],
    this.categories = const [],
  });
  final List<VocabWord> words;
  final List<Map<String, dynamic>> reviews;
  final List<String> categories;
  factory Notebook.fromJson(Map<String, dynamic> data) {
    if (data['version'] != 1) throw const FormatException('지원하지 않는 단어장 버전입니다.');
    final words = (data['words'] as List)
        .map((e) => VocabWord(Map<String, dynamic>.from(e)))
        .toList();
    if (words.any((w) => w.word.trim().isEmpty || w.meaning.trim().isEmpty) ||
        words.map((w) => w.id).toSet().length != words.length) {
      throw const FormatException('단어장 데이터가 올바르지 않습니다.');
    }
    return Notebook(
      words: words,
      reviews: (data['reviews'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      categories: (data['categories'] as List? ?? []).cast<String>(),
    );
  }
  Map<String, dynamic> toJson() => {
    'version': 1,
    'words': words.map((w) => w.toJson()).toList(),
    'reviews': reviews,
    'categories': categories,
  };
  Notebook replace({
    List<VocabWord>? words,
    List<Map<String, dynamic>>? reviews,
    List<String>? categories,
  }) => Notebook(
    words: words ?? this.words,
    reviews: reviews ?? this.reviews,
    categories: categories ?? this.categories,
  );
}
