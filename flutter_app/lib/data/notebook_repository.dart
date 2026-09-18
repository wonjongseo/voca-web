import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/vocabulary.dart';

abstract class NotebookRepository {
  Future<Notebook> load();
  Future<void> putWord(VocabWord word);
  Future<void> deleteWord(String id);
  Future<void> review(VocabWord word, Map<String, dynamic> review);
  Future<void> setCategories(List<String> categories);
}

class GuestRepository implements NotebookRepository {
  GuestRepository(this.preferences);
  final SharedPreferences preferences;
  Notebook _book = const Notebook();
  @override
  Future<Notebook> load() async {
    final raw = preferences.getString(guestStorageKey);
    _book = raw == null ? const Notebook() : Notebook.fromJson(jsonDecode(raw));
    return _book;
  }

  Future<void> _save(Notebook next) async {
    if (!await preferences.setString(
      guestStorageKey,
      jsonEncode(next.toJson()),
    )) {
      throw StateError('기기에 저장하지 못했습니다.');
    }
    _book = next;
  }

  @override
  Future<void> putWord(VocabWord word) => _save(
    _book.replace(words: [..._book.words.where((w) => w.id != word.id), word]),
  );
  @override
  Future<void> deleteWord(String id) => _save(
    _book.replace(words: _book.words.where((w) => w.id != id).toList()),
  );
  @override
  Future<void> review(VocabWord word, Map<String, dynamic> review) => _save(
    _book.replace(
      words: _book.words.map((w) => w.id == word.id ? word : w).toList(),
      reviews: [..._book.reviews, review],
    ),
  );
  @override
  Future<void> setCategories(List<String> categories) =>
      _save(_book.replace(categories: categories));
}

class CloudRepository implements NotebookRepository {
  CloudRepository(this.firestore, this.uid, {this.groupId});
  final FirebaseFirestore firestore;
  final String uid;
  final String? groupId;
  DocumentReference<Map<String, dynamic>> get root => groupId == null
      ? firestore.collection('users').doc(uid)
      : firestore.collection('groups').doc(groupId);
  @override
  Future<Notebook> load() async {
    // Explicit refresh only: no billed, always-on snapshot listener.
    final metadata = await root.get();
    final words = <VocabWord>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? last;
    do {
      Query<Map<String, dynamic>> query = root
          .collection('words')
          .orderBy(FieldPath.documentId)
          .limit(200);
      if (last != null) query = query.startAfterDocument(last);
      final page = await query.get();
      words.addAll(
        page.docs.map(
          (d) => VocabWord({...d.data(), 'id': d.id}).copy({'updatedAt': null}),
        ),
      );
      if (page.docs.length < 200) break;
      last = page.docs.last;
    } while (true);
    final reviews = await root
        .collection('reviews')
        .orderBy('date', descending: true)
        .limit(2000)
        .get();
    return Notebook(
      words: words,
      reviews: reviews.docs.map((d) => d.data()).toList(),
      categories: (metadata.data()?['categories'] as List? ?? [])
          .cast<String>(),
    );
  }

  Map<String, dynamic> _wordData(VocabWord word) => {
    ...word.toJson(),
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': uid,
  };
  @override
  Future<void> putWord(VocabWord word) =>
      root.collection('words').doc(word.id).set(_wordData(word));
  @override
  Future<void> deleteWord(String id) =>
      root.collection('words').doc(id).delete();
  @override
  Future<void> review(VocabWord word, Map<String, dynamic> review) async {
    final batch = firestore.batch();
    batch.set(root.collection('words').doc(word.id), _wordData(word));
    batch.set(root.collection('reviews').doc(), review);
    await batch.commit();
  }

  @override
  Future<void> setCategories(List<String> categories) => root.set({
    'version': 1,
    'categories': categories,
  }, SetOptions(merge: true));
}
