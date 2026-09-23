import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/vocabulary.dart';

const _reviewStorageVersion = 3;
const _chunkSchemaVersion = 4;
const _chunkCount = 16;

class ChunkLoadResult {
  const ChunkLoadResult({
    required this.notebook,
    required this.versions,
  });

  final Notebook notebook;
  final Map<String, int> versions;
}

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

  CollectionReference<Map<String, dynamic>> get chunks =>
      root.collection('wordChunks');

  String _reviewId(Map<String, dynamic> review, int index) {
    final id = '${review['id'] ?? ''}'.trim();
    if (id.isNotEmpty) return id;
    return 'legacy:${review['date']}:${review['correct'] == true ? 1 : 0}:$index';
  }

  String _encodeReviewEvent(Map<String, dynamic> review, int index) {
    return jsonEncode([
      _reviewId(review, index),
      '${review['date'] ?? ''}',
      review['correct'] == true ? 1 : 0,
    ]);
  }

  Map<String, dynamic>? _decodeReviewEvent(String raw, String wordId) {
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
    final matches = reviews
        .where((review) => review['wordId'] == wordId)
        .toList();
    return [
      for (var i = 0; i < matches.length; i++)
        _encodeReviewEvent(matches[i], i),
    ];
  }

  String chunkIdForWord(String wordId) {
    var hash = 0;
    for (final unit in wordId.codeUnits) {
      hash = ((hash * 31) + unit) & 0xffffffff;
    }
    return (hash % _chunkCount).toString().padLeft(2, '0');
  }

  Map<String, int> _versionsFromRoot(Map<String, dynamic>? data) {
    final raw = data?['chunkVersions'];
    if (raw is! Map) return <String, int>{};
    return raw.map(
      (key, value) => MapEntry(
        '$key',
        (value as num? ?? 0).toInt(),
      ),
    );
  }

  Map<String, dynamic> _chunkPayload(Notebook notebook, String chunkId) {
    final words = <String, dynamic>{};
    for (final word in notebook.words) {
      if (chunkIdForWord(word.id) != chunkId) continue;
      words[word.id] = <String, dynamic>{
        ...word.toJson(),
        '_reviewEvents': _reviewEventsFor(notebook.reviews, word.id),
      };
    }
    return words;
  }

  Notebook _applyChunkDocs(
    Notebook base,
    Iterable<DocumentSnapshot<Map<String, dynamic>>> docs,
    List<String> rootCategories,
  ) {
    final wordsById = <String, VocabWord>{
      for (final word in base.words) word.id: word,
    };
    final reviewsByWord = <String, List<Map<String, dynamic>>>{};
    for (final review in base.reviews) {
      final wordId = '${review['wordId'] ?? ''}';
      if (wordId.isEmpty) continue;
      reviewsByWord.putIfAbsent(wordId, () => []).add(review);
    }

    for (final doc in docs) {
      final chunkId = doc.id;

      final removeIds = wordsById.values
          .where((word) => chunkIdForWord(word.id) == chunkId)
          .map((word) => word.id)
          .toList();
      for (final id in removeIds) {
        wordsById.remove(id);
        reviewsByWord.remove(id);
      }

      final rawWords = doc.data()?['words'];
      if (rawWords is! Map) continue;

      for (final entry in rawWords.entries) {
        if (entry.value is! Map) continue;
        final id = '${entry.key}';
        final data = Map<String, dynamic>.from(entry.value as Map);
        final events = data.remove('_reviewEvents');
        data['id'] = id;
        wordsById[id] = VocabWord(data);

        if (events is List) {
          reviewsByWord[id] = events
              .whereType<String>()
              .map((event) => _decodeReviewEvent(event, id))
              .whereType<Map<String, dynamic>>()
              .toList();
        }
      }
    }

    final words = wordsById.values.toList()
      ..sort((a, b) {
        final ac = (a.data['created'] as num? ?? 0).toInt();
        final bc = (b.data['created'] as num? ?? 0).toInt();
        return bc.compareTo(ac);
      });

    final categories = <String>{
      ...rootCategories,
      ...words.map((word) => word.category).where((value) => value.isNotEmpty),
    }.toList()
      ..sort();

    return Notebook(
      words: words,
      reviews: reviewsByWord.values.expand((items) => items).toList(),
      categories: categories,
    );
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadLegacyWordDocs() async {
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
    final snap = await root.collection('reviews').get();
    for (final doc in snap.docs) {
      result.add({...doc.data(), 'id': 'legacy:${doc.id}'});
    }
    return result;
  }

  Future<void> _commitBatches(
    List<void Function(WriteBatch batch)> operations,
  ) async {
    for (var start = 0; start < operations.length; start += 450) {
      final batch = firestore.batch();
      for (final op in operations.skip(start).take(450)) {
        op(batch);
      }
      await batch.commit();
    }
  }

  Future<ChunkLoadResult> _migrateLegacy(
    DocumentSnapshot<Map<String, dynamic>> metadata,
  ) async {
    final wordDocs = await _loadLegacyWordDocs();
    final activeDocs = wordDocs
        .where((doc) => doc.data()['deleted'] != true)
        .toList();

    final words = <VocabWord>[];
    final reviews = <Map<String, dynamic>>[];

    for (final doc in activeDocs) {
      final data = Map<String, dynamic>.from(doc.data());
      final events = data.remove('_reviewEvents');
      data.remove('updatedAt');
      data.remove('updatedBy');
      data.remove('deleted');
      data['id'] = doc.id;
      words.add(VocabWord(data));

      if (events is List) {
        reviews.addAll(
          events
              .whereType<String>()
              .map((event) => _decodeReviewEvent(event, doc.id))
              .whereType<Map<String, dynamic>>(),
        );
      }
    }

    final storageVersion =
        (metadata.data()?['reviewStorageVersion'] as num?)?.toInt();
    if (storageVersion != _reviewStorageVersion) {
      reviews
        ..clear()
        ..addAll(await _loadLegacyReviews());
    }

    final storedCategories =
        (metadata.data()?['categories'] as List? ?? const [])
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty);

    final notebook = Notebook(
      words: words,
      reviews: reviews,
      categories: <String>{
        ...storedCategories,
        ...words.map((word) => word.category).where((value) => value.isNotEmpty),
      }.toList()
        ..sort(),
    );

    final versions = <String, int>{};
    final operations = <void Function(WriteBatch batch)>[];

    for (var i = 0; i < _chunkCount; i++) {
      final chunkId = i.toString().padLeft(2, '0');
      final payload = _chunkPayload(notebook, chunkId);
      if (payload.isEmpty) continue;
      versions[chunkId] = 1;
      operations.add(
        (batch) => batch.set(
          chunks.doc(chunkId),
          {
            'version': 1,
            'words': payload,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        ),
      );
    }

    operations.add(
      (batch) => batch.set(
        root,
        {
          'version': 1,
          'categories': notebook.categories,
          'reviewStorageVersion': _reviewStorageVersion,
          'storageSchemaVersion': _chunkSchemaVersion,
          'chunkCount': _chunkCount,
          'chunkVersions': versions,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': uid,
        },
        SetOptions(merge: true),
      ),
    );

    await _commitBatches(operations);
    return ChunkLoadResult(notebook: notebook, versions: versions);
  }

  Future<ChunkLoadResult> loadFullChunked() async {
    final metadata = await root.get();
    if ((metadata.data()?['storageSchemaVersion'] as num?)?.toInt() !=
        _chunkSchemaVersion) {
      return _migrateLegacy(metadata);
    }

    final snap = await chunks.get();
    final categories = (metadata.data()?['categories'] as List? ?? const [])
        .whereType<String>()
        .toList();

    return ChunkLoadResult(
      notebook: _applyChunkDocs(const Notebook(), snap.docs, categories),
      versions: _versionsFromRoot(metadata.data()),
    );
  }

  Future<ChunkLoadResult> loadChangedChunks(
    Notebook base,
    Map<String, int> localVersions,
  ) async {
    final metadata = await root.get();
    if ((metadata.data()?['storageSchemaVersion'] as num?)?.toInt() !=
        _chunkSchemaVersion) {
      return _migrateLegacy(metadata);
    }

    final remoteVersions = _versionsFromRoot(metadata.data());
    final changedIds = remoteVersions.entries
        .where((entry) => localVersions[entry.key] != entry.value)
        .map((entry) => entry.key)
        .toList();

    final changedDocs = await Future.wait(
      changedIds.map((id) => chunks.doc(id).get()),
    );

    final categories = (metadata.data()?['categories'] as List? ?? const [])
        .whereType<String>()
        .toList();

    return ChunkLoadResult(
      notebook: _applyChunkDocs(base, changedDocs, categories),
      versions: remoteVersions,
    );
  }

  Future<Map<String, int>> writeDirtyChunks(
    Notebook notebook,
    Set<String> dirtyWordIds,
    bool metadataDirty,
    Map<String, int> currentVersions,
  ) async {
    final dirtyChunks = dirtyWordIds.map(chunkIdForWord).toSet();
    if (dirtyChunks.isEmpty && !metadataDirty) return currentVersions;

    final versions = Map<String, int>.from(currentVersions);
    final operations = <void Function(WriteBatch batch)>[];

    for (final chunkId in dirtyChunks) {
      final nextVersion = (versions[chunkId] ?? 0) + 1;
      versions[chunkId] = nextVersion;
      operations.add(
        (batch) => batch.set(
          chunks.doc(chunkId),
          {
            'version': nextVersion,
            'words': _chunkPayload(notebook, chunkId),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        ),
      );
    }

    operations.add(
      (batch) => batch.set(
        root,
        {
          'version': 1,
          'categories': notebook.categories,
          'reviewStorageVersion': _reviewStorageVersion,
          'storageSchemaVersion': _chunkSchemaVersion,
          'chunkCount': _chunkCount,
          'chunkVersions': versions,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': uid,
        },
        SetOptions(merge: true),
      ),
    );

    await _commitBatches(operations);
    return versions;
  }

  @override
  Future<Notebook> load() async => (await loadFullChunked()).notebook;

  // Cloud write는 LeafyController가 local-first debounce 후 writeDirtyChunks로 수행한다.
  @override
  Future<void> putWord(VocabWord word) async {}

  @override
  Future<void> putWords(List<VocabWord> words) async {}

  @override
  Future<void> deleteWord(String id) async {}

  @override
  Future<void> review(VocabWord word, Map<String, dynamic> review) async {}

  @override
  Future<void> replaceReviewEvents(
    Set<String> wordIds,
    List<Map<String, dynamic>> reviews,
  ) async {}

  @override
  Future<void> setCategories(List<String> categories) async {}

  Future<void> mergeGuestNotebook(Notebook guest) async {
    final loaded = await loadFullChunked();
    final current = loaded.notebook;
    final guestIds = guest.words.map((word) => word.id).toSet();
    final merged = Notebook(
      words: [
        ...guest.words,
        ...current.words.where((word) => !guestIds.contains(word.id)),
      ],
      reviews: [...current.reviews, ...guest.reviews],
      categories: <String>{
        ...current.categories,
        ...guest.categories,
        ...guest.words.map((word) => word.category).where((value) => value.isNotEmpty),
      }.toList()
        ..sort(),
    );

    final dirtyIds = merged.words.map((word) => word.id).toSet();
    await writeDirtyChunks(
      merged,
      dirtyIds,
      true,
      loaded.versions,
    );
  }
}
