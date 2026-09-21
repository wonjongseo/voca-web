import 'package:uuid/uuid.dart';

const guestStorageKey = 'leafy-guest-v1';

String dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class VocabWord {
  VocabWord(Map<String, dynamic> json) : data = Map.unmodifiable(json);
  final Map<String, dynamic> data;

  factory VocabWord.create(String word, String meaning) => VocabWord({
        'id': const Uuid().v4(),
        'word': word,
        'meaning': meaning,
        'meaningEntries': meaning.trim().isEmpty ? <String>[] : <String>[meaning],
        'example': '',
        'translation': '',
        'examples': <Map<String, String>>[],
        'synonyms': '',
        'synonymEntries': <String>[],
        'memo': '',
        'category': '',
        'favorite': false,
        'level': 0,
        'due': 0,
        'created': DateTime.now().millisecondsSinceEpoch,
      });

  String get id => '${data['id'] ?? ''}';
  String get word => '${data['word'] ?? ''}';
  String get meaning => '${data['meaning'] ?? ''}';
  String text(String key) => '${data[key] ?? ''}';
  bool get favorite => data['favorite'] == true;
  int get level => (data['level'] as num? ?? 0).toInt();
  int get due => (data['due'] as num? ?? 0).toInt();
  String get category => text('category').trim();

  List<String> get meanings {
    final entries = (data['meaningEntries'] as List?)
        ?.whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (entries != null && entries.isNotEmpty) return entries;
    final fallback = meaning.trim();
    return fallback.isEmpty ? <String>[] : <String>[fallback];
  }

  List<Map<String, String>> get examples {
    final raw = data['examples'];
    if (raw is List) {
      final values = raw.whereType<Map>().map((entry) => <String, String>{
            'text': '${entry['text'] ?? ''}'.trim(),
            'translation': '${entry['translation'] ?? ''}'.trim(),
          }).where((entry) =>
              entry['text']!.isNotEmpty || entry['translation']!.isNotEmpty).toList();
      if (values.isNotEmpty) return values;
    }
    final example = text('example').trim();
    final translation = text('translation').trim();
    return example.isEmpty && translation.isEmpty
        ? <Map<String, String>>[]
        : <Map<String, String>>[
            {'text': example, 'translation': translation},
          ];
  }

  List<String> get synonymEntries {
    final raw = data['synonymEntries'];
    if (raw is List) {
      final values = raw
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (values.isNotEmpty) return values;
    }
    return text('synonyms')
        .split(RegExp(r'[,;\n]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  VocabWord copy(Map<String, dynamic> changes) =>
      VocabWord({...data, ...changes});

  Map<String, dynamic> toJson() => Map<String, dynamic>.of(data)
    ..remove('updatedAt')
    ..remove('updatedBy')
    ..remove('_reviewEvents');

  VocabWord schedule(bool correct, DateTime now) {
    final next = correct ? (level + 1).clamp(0, 6).toInt() : 0;
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
    if (data['version'] != 1) {
      throw const FormatException('지원하지 않는 단어장 버전입니다.');
    }
    final rawWords = data['words'];
    if (rawWords is! List) {
      throw const FormatException('단어장 데이터가 올바르지 않습니다.');
    }
    final words = rawWords
        .whereType<Map>()
        .map((entry) => VocabWord(Map<String, dynamic>.from(entry)))
        .toList();
    if (words.any((word) => word.word.trim().isEmpty || word.meaning.trim().isEmpty) ||
        words.map((word) => word.id).toSet().length != words.length) {
      throw const FormatException('단어장 데이터가 올바르지 않습니다.');
    }
    final rawReviews = data['reviews'];
    final reviews = rawReviews is List
        ? rawReviews.whereType<Map>().map((entry) {
            final review = Map<String, dynamic>.from(entry);
            if (review['id'] != null && review['id'] is! String) review.remove('id');
            return review;
          }).where((review) =>
              review['date'] is String &&
              review['correct'] is bool &&
              review['wordId'] is String).toList()
        : <Map<String, dynamic>>[];
    final storedCategories = (data['categories'] as List? ?? const [])
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    final categories = <String>{
      ...storedCategories,
      ...words.map((word) => word.category).where((value) => value.isNotEmpty),
    }.toList()
      ..sort();
    return Notebook(words: words, reviews: reviews, categories: categories);
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'words': words.map((word) => word.toJson()).toList(),
        'reviews': reviews,
        'categories': categories,
      };

  Notebook replace({
    List<VocabWord>? words,
    List<Map<String, dynamic>>? reviews,
    List<String>? categories,
  }) =>
      Notebook(
        words: words ?? this.words,
        reviews: reviews ?? this.reviews,
        categories: categories ?? this.categories,
      );
}
