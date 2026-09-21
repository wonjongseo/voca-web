import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/vocabulary.dart';

const _reviewStorageVersion = 3;

abstract class NotebookRepository {
  Future<Notebook> load();
  Future<void> putWord(VocabWord word);
  Future<void> putWords(List<VocabWord> words);
  Future<void> deleteWord(String id);
  Future<void> review(VocabWord word, Map<String, dynamic> review);
  Future<void> replaceReviewEvents(
    Set<String> wordIds,
    List<Map<String, dynamic>> reviews,
  );
  Future<void> setCategories(List<String> categories);
}

class GuestRepository implements NotebookRepository {
  GuestRepository(this.preferences);

  final SharedPreferences preferences;
  Notebook _book = const Notebook();

  @override
  Future<Notebook> load() async {
    final raw = preferences.getString(guestStorageKey);
    _book = raw == null
        ? const Notebook()
        : Notebook.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return _book;
  }

  Future<void> replaceAll(Notebook book) => _save(book);

  Future<void> _save(Notebook next) async {
    final saved = await preferences.setString(
      guestStorageKey,
      jsonEncode(next.toJson()),
    );
    if (!saved) throw StateError('기기에 저장하지 못했습니다.');
    _book = next;
  }

  @override
  Future<void> putWord(VocabWord word) => _save(
        _book.replace(
          words: [
            ..._book.words.where((candidate) => candidate.id != word.id),
            word,
          ],
        ),
      );

  @override
  Future<void> putWords(List<VocabWord> words) {
    if (words.isEmpty) return Future<void>.value();

    final ids = words.map((word) => word.id).toSet();
    return _save(
      _book.replace(
        words: [
          ..._book.words.where((word) => !ids.contains(word.id)),
          ...words,
        ],
      ),
    );
  }

  @override
  Future<void> deleteWord(String id) => _save(
        _book.replace(
          words: _book.words.where((word) => word.id != id).toList(),
          reviews: _book.reviews
              .where((review) => review['wordId'] != id)
              .toList(),
        ),
      );

  @override
  Future<void> review(VocabWord word, Map<String, dynamic> review) => _save(
        _book.replace(
          words: _book.words
              .map((candidate) => candidate.id == word.id ? word : candidate)
              .toList(),
          reviews: [..._book.reviews, review],
        ),
      );

  @override
  Future<void> replaceReviewEvents(
    Set<String> wordIds,
    List<Map<String, dynamic>> reviews,
  ) {
    if (wordIds.isEmpty) return Future<void>.value();
    return _save(_book.replace(reviews: reviews));
  }

  @override
  Future<void> setCategories(List<String> categories) =>
      _save(_book.replace(categories: categories));
}

class CloudRepository implements NotebookRepository {
  CloudRepository(
    this.firestore,
    this.uid, {
    this.groupId,
  });

  final FirebaseFirestore firestore;
  final String uid;
  final String? groupId;

  DocumentReference<Map<String, dynamic>> get root => groupId == null
      ? firestore.collection('users').doc(uid)
      : firestore.collection('groups').doc(groupId);

  String _reviewId(Map<String, dynamic> review, int wordIndex) {
    final id = '${review['id'] ?? ''}'.trim();
    if (id.isNotEmpty) return id;
    return 'legacy:${review['date']}:${review['correct'] == true ? 1 : 0}:$wordIndex';
  }

  String _encodeReviewEvent(
    Map<String, dynamic> review,
    int wordIndex,
  ) {
    return jsonEncode([
      _reviewId(review, wordIndex),
      '${review['date'] ?? ''}',
      review['correct'] == true ? 1 : 0,
    ]);
  }

  Map<String, dynamic>? _decodeReviewEvent(
    String raw,
    String wordId,
  ) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List ||
          parsed.length < 3 ||
          parsed[0] is! String ||
          parsed[1] is! String ||
          (parsed[2] != 0 && parsed[2] != 1)) {
        return null;
      }
      return <String, dynamic>{
        'id': parsed[0],
        'date': parsed[1],
        'correct': parsed[2] == 1,
        'wordId': wordId,
      };
    } catch (_) {
      return null;
    }
  }

  List<String> _reviewEventsFor(
    List<Map<String, dynamic>> reviews,
    String wordId,
  ) {
    final matches =
        reviews.where((review) => review['wordId'] == wordId).toList();
    return [
      for (var index = 0; index < matches.length; index++)
        _encodeReviewEvent(matches[index], index),
    ];
  }

  Map<String, dynamic> _wordData(
    VocabWord word, {
    Object? reviewEvents,
  }) {
    return <String, dynamic>{
      ...word.toJson(),
      if (reviewEvents != null) '_reviewEvents': reviewEvents,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    };
  }

  VocabWord _wordFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = Map<String, dynamic>.from(doc.data())
      ..remove('_reviewEvents')
      ..remove('updatedAt')
      ..remove('updatedBy');
    return VocabWord({...data, 'id': doc.id});
  }

  List<Map<String, dynamic>> _reviewsFromWordDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final raw = doc.data()['_reviewEvents'];
    if (raw is! List) return [];
    return raw
        .whereType<String>()
        .map((event) => _decodeReviewEvent(event, doc.id))
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadWordDocs() async {
    final result = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? last;

    while (true) {
      Query<Map<String, dynamic>> query = root
          .collection('words')
          .orderBy(FieldPath.documentId)
          .limit(300);
      if (last != null) query = query.startAfterDocument(last);

      final page = await query.get();
      result.addAll(page.docs);

      if (page.docs.length < 300) break;
      last = page.docs.last;
    }

    return result;
  }

  Future<List<Map<String, dynamic>>> _loadLegacyReviews() async {
    final result = <Map<String, dynamic>>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? last;

    while (true) {
      Query<Map<String, dynamic>> query = root
          .collection('reviews')
          .orderBy(FieldPath.documentId)
          .limit(500);
      if (last != null) query = query.startAfterDocument(last);

      final page = await query.get();
      for (final doc in page.docs) {
        result.add({
          ...doc.data(),
          'id': 'legacy:${doc.id}',
        });
      }

      if (page.docs.length < 500) break;
      last = page.docs.last;
    }

    return result;
  }

  Future<void> _commitBatches(
    List<void Function(WriteBatch batch)> operations,
  ) async {
    if (operations.isEmpty) return;

    for (var start = 0; start < operations.length; start += 450) {
      final batch = firestore.batch();
      for (final operation in operations.skip(start).take(450)) {
        operation(batch);
      }
      await batch.commit();
    }
  }

  Future<void> _migrateLegacyReviews(
    List<VocabWord> words,
    List<Map<String, dynamic>> legacyReviews,
  ) async {
    final operations = <void Function(WriteBatch batch)>[];

    for (final word in words) {
      final events = _reviewEventsFor(legacyReviews, word.id);
      if (events.isEmpty) continue;

      operations.add(
        (batch) => batch.set(
          root.collection('words').doc(word.id),
          {
            '_reviewEvents': events,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': uid,
          },
          SetOptions(merge: true),
        ),
      );
    }

    operations.add(
      (batch) => batch.set(
        root,
        {
          'reviewStorageVersion': _reviewStorageVersion,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': uid,
        },
        SetOptions(merge: true),
      ),
    );

    await _commitBatches(operations);
  }

  @override
  Future<Notebook> load() async {
    final metadataFuture = root.get();
    final wordsFuture = _loadWordDocs();

    final metadata = await metadataFuture;
    final wordDocs = await wordsFuture;
    final words = wordDocs.map(_wordFromDoc).toList();

    final storedCategories = (metadata.data()?['categories'] as List? ?? const [])
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);

    final categories = <String>{
      ...storedCategories,
      ...words.map((word) => word.category).where((value) => value.isNotEmpty),
    }.toList()
      ..sort();

    final storageVersion =
        (metadata.data()?['reviewStorageVersion'] as num?)?.toInt();

    if (storageVersion == _reviewStorageVersion) {
      return Notebook(
        words: words,
        reviews: wordDocs.expand(_reviewsFromWordDoc).toList(),
        categories: categories,
      );
    }

    final legacyReviews = await _loadLegacyReviews();
    await _migrateLegacyReviews(words, legacyReviews);

    return Notebook(
      words: words,
      reviews: legacyReviews,
      categories: categories,
    );
  }

  @override
  Future<void> putWord(VocabWord word) {
    return root.collection('words').doc(word.id).set(
          _wordData(word),
          SetOptions(merge: true),
        );
  }

  @override
  Future<void> putWords(List<VocabWord> words) async {
    if (words.isEmpty) return;

    final operations = <void Function(WriteBatch batch)>[
      for (final word in words)
        (batch) => batch.set(
              root.collection('words').doc(word.id),
              _wordData(word),
              SetOptions(merge: true),
            ),
    ];

    await _commitBatches(operations);
  }

  @override
  Future<void> deleteWord(String id) {
    return root.collection('words').doc(id).delete();
  }

  @override
  Future<void> review(
    VocabWord word,
    Map<String, dynamic> review,
  ) {
    final event = _encodeReviewEvent(review, 0);
    return root.collection('words').doc(word.id).set(
          _wordData(
            word,
            reviewEvents: FieldValue.arrayUnion([event]),
          ),
          SetOptions(merge: true),
        );
  }

  @override
  Future<void> replaceReviewEvents(
    Set<String> wordIds,
    List<Map<String, dynamic>> reviews,
  ) async {
    if (wordIds.isEmpty) return;

    final operations = <void Function(WriteBatch batch)>[
      for (final wordId in wordIds)
        (batch) => batch.set(
              root.collection('words').doc(wordId),
              {
                '_reviewEvents': _reviewEventsFor(reviews, wordId),
                'updatedAt': FieldValue.serverTimestamp(),
                'updatedBy': uid,
              },
              SetOptions(merge: true),
            ),
    ];

    await _commitBatches(operations);
  }

  @override
  Future<void> setCategories(List<String> categories) {
    return root.set(
      {
        'version': 1,
        'categories': categories,
        'reviewStorageVersion': _reviewStorageVersion,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> mergeGuestNotebook(Notebook guest) async {
    final current = await load();

    final categories = <String>{
      ...current.categories,
      ...guest.categories,
      ...current.words
          .map((word) => word.category)
          .where((value) => value.isNotEmpty),
      ...guest.words
          .map((word) => word.category)
          .where((value) => value.isNotEmpty),
    }.toList()
      ..sort();

    final operations = <void Function(WriteBatch batch)>[];

    for (final word in guest.words) {
      final events = _reviewEventsFor(guest.reviews, word.id);
      operations.add(
        (batch) => batch.set(
          root.collection('words').doc(word.id),
          _wordData(
            word,
            reviewEvents:
                events.isEmpty ? null : FieldValue.arrayUnion(events),
          ),
          SetOptions(merge: true),
        ),
      );
    }

    operations.add(
      (batch) => batch.set(
        root,
        {
          'version': 1,
          'categories': categories,
          'reviewStorageVersion': _reviewStorageVersion,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': uid,
        },
        SetOptions(merge: true),
      ),
    );

    await _commitBatches(operations);
  }
}
