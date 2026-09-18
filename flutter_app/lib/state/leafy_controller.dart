import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../data/notebook_repository.dart';
import '../domain/vocabulary.dart';

class LeafyController extends ChangeNotifier {
  LeafyController(this.preferences, {this.auth, this.firestore});
  final SharedPreferences preferences;
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
  StreamSubscription<User?>? _authSubscription;
  NotebookRepository? _repository;
  Notebook book = const Notebook();
  User? user;
  String? groupId;
  String? error;
  bool busy = true;
  bool loaded = false;
  int _generation = 0;
  Future<void>? _googleInitialization;
  bool get autoSpeak => preferences.getBool('leafy-auto-speak') ?? false;
  String get accent => preferences.getString('leafy-accent') ?? 'en-US';
  List<VocabWord> get due => book.words
      .where((w) => w.due <= DateTime.now().millisecondsSinceEpoch)
      .toList();
  Set<String> get wrongIds {
    final last = <String, bool>{};
    final reviews = [...book.reviews]
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    for (final r in reviews) {
      last[r['wordId'] as String] = r['correct'] == true;
    }
    return last.entries.where((e) => !e.value).map((e) => e.key).toSet();
  }

  Future<void> start() async {
    if (auth == null) {
      await selectScope();
    } else {
      _authSubscription = auth!.authStateChanges().listen((next) {
        user = next;
        unawaited(selectScope());
      });
    }
  }

  Future<void> selectScope([String? group]) async {
    final generation = ++_generation;
    groupId = user == null ? null : group;
    busy = true;
    loaded = false;
    error = null;
    book = const Notebook();
    final repository = user == null
        ? GuestRepository(preferences)
        : CloudRepository(firestore!, user!.uid, groupId: groupId);
    _repository = repository;
    notifyListeners();
    try {
      final next = await repository.load();
      if (generation != _generation) return;
      book = next;
      loaded = true;
    } catch (e) {
      if (generation == _generation)
        error = '불러오지 못했습니다. 새로고침으로 다시 시도하세요. ($e)';
    } finally {
      if (generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _mutate(
    Future<void> Function(NotebookRepository) write,
    Notebook Function() next,
  ) async {
    if (busy || !loaded) throw StateError('단어장을 먼저 불러오세요.');
    final generation = _generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await write(_repository!);
      if (generation == _generation) book = next();
    } catch (e) {
      if (generation == _generation) error = '저장하지 못했습니다. 다시 시도하세요. ($e)';
      rethrow;
    } finally {
      if (generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> save(VocabWord word) => _mutate(
    (r) => r.putWord(word),
    () => book.replace(
      words: [...book.words.where((w) => w.id != word.id), word],
    ),
  );
  Future<void> delete(String id) => _mutate(
    (r) => r.deleteWord(id),
    () => book.replace(words: book.words.where((w) => w.id != id).toList()),
  );
  Future<void> grade(VocabWord word, bool correct) {
    final now = DateTime.now();
    final nextWord = word.schedule(correct, now);
    final review = <String, dynamic>{
      'date': dateKey(now),
      'wordId': word.id,
      'correct': correct,
    };
    return _mutate(
      (r) => r.review(nextWord, review),
      () => book.replace(
        words: book.words.map((w) => w.id == word.id ? nextWord : w).toList(),
        reviews: [...book.reviews, review],
      ),
    );
  }

  Future<void> categories(List<String> values) => _mutate(
    (r) => r.setCategories(values),
    () => book.replace(categories: values),
  );
  Future<void> setAutoSpeak(bool value) async {
    await preferences.setBool('leafy-auto-speak', value);
    notifyListeners();
  }

  Future<void> setAccent(String value) async {
    await preferences.setString('leafy-accent', value);
    notifyListeners();
  }

  Future<void> signIn(
    String email,
    String password, {
    bool register = false,
  }) async {
    if (register) {
      await auth!.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } else {
      await auth!.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    }
  }

  Future<void> googleSignIn() async {
    final provider = GoogleAuthProvider();
    if (kIsWeb) {
      await auth!.signInWithPopup(provider);
    } else {
      const clientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
      const serverId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
      _googleInitialization ??= GoogleSignIn.instance.initialize(
        clientId: clientId.isEmpty ? null : clientId,
        serverClientId: serverId.isEmpty ? null : serverId,
      );
      await _googleInitialization;
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null) throw StateError('Google 인증 토큰을 받지 못했습니다.');
      await auth!.signInWithCredential(GoogleAuthProvider.credential(idToken: token));
    }
  }

  Future<String> createGroup(String name) async {
    final uid = user!.uid;
    final ref = firestore!.collection('groups').doc();
    await ref.set({
      'name': name.trim(),
      'ownerUid': uid,
      'memberUids': {uid: true},
      'version': 1,
      'categories': [],
      'createdAt': FieldValue.serverTimestamp(),
    });
    await selectScope(ref.id);
    return ref.id;
  }

  Future<void> addMember(String uid) async {
    final ref = firestore!.collection('groups').doc(groupId);
    final doc = await ref.get();
    if (doc.data()?['ownerUid'] != user!.uid)
      throw StateError('그룹 소유자만 멤버를 추가할 수 있습니다.');
    await ref.update({'memberUids.${uid.trim()}': true});
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
