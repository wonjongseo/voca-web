import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/notebook_repository.dart';
import '../domain/quiz_logic.dart';
import '../domain/vocabulary.dart';

// FLUTTER_WEB_PARITY_MODERN_UI_V2
class LeafyController extends ChangeNotifier {
  LeafyController(
    this.preferences, {
    this.auth,
    this.firestore,
  });

  static const _guestDirtyKey = 'leafy-guest-dirty-v1';
  static const _quizHistoryKey = 'leafy-quiz-history-v1';
  static const _cloudCachePrefix = 'leafy-cloud-cache-v3';

  final SharedPreferences preferences;
  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;

  StreamSubscription<User?>? _authSubscription;
  NotebookRepository? _repository;
  String? _authUid;
  Future<void>? _googleInitialization;

  Notebook book = const Notebook();
  User? user;
  String? groupId;
  String? error;
  bool busy = true;
  bool loaded = false;
  int _generation = 0;

  bool get autoSpeak => preferences.getBool('leafy-auto-speak') ?? false;
  String get accent => preferences.getString('leafy-accent') ?? 'en-US';

  List<VocabWord> get due => book.words
      .where((word) => word.due <= DateTime.now().millisecondsSinceEpoch)
      .toList();

  Set<String> get wrongIds => book.words
      .where((word) => relearningProgress(book.reviews, word.id).active)
      .map((word) => word.id)
      .toSet();

  RelearningProgress wrongProgress(String wordId) =>
      relearningProgress(book.reviews, wordId);

  String _cacheKey(String uid, String? group) =>
      '$_cloudCachePrefix:$uid:${group ?? 'personal'}';

  Notebook? _readCloudCache(String uid, String? group) {
    try {
      final raw = preferences.getString(_cacheKey(uid, group));
      return raw == null
          ? null
          : Notebook.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCloudCache(
    String uid,
    String? group,
    Notebook notebook,
  ) {
    return preferences.setString(
      _cacheKey(uid, group),
      jsonEncode(notebook.toJson()),
    );
  }

  Map<String, List<String>> _quizHistory() {
    try {
      final raw = preferences.getString(_quizHistoryKey);
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) => MapEntry(
          '$key',
          value is List ? value.whereType<String>().toList() : <String>[],
        ),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> _rememberQuizWords(
    String modeKey,
    List<VocabWord> pool,
    List<VocabWord> selected,
  ) async {
    final history = _quizHistory();
    final poolIds = pool.map((word) => word.id).toSet();
    final previous =
        (history[modeKey] ?? []).where(poolIds.contains).toList();

    final picked = selected.map((word) => word.id).toList();
    final pickedIds = picked.toSet();

    history[modeKey] = [
      ...previous.where((id) => !pickedIds.contains(id)),
      ...picked,
    ].where(poolIds.contains).toList();

    await preferences.setString(_quizHistoryKey, jsonEncode(history));
  }

  List<VocabWord> _balancedWords(
    String modeKey,
    List<VocabWord> pool,
    int limit,
  ) {
    final history = _quizHistory();
    final poolIds = pool.map((word) => word.id).toSet();
    final seen = (history[modeKey] ?? []).where(poolIds.contains).toList();
    final seenIndex = <String, int>{
      for (var index = 0; index < seen.length; index++) seen[index]: index,
    };

    return weightedWordsWithoutReplacement(
      pool,
      limit,
      (word) {
        final mastery = masterySelectionWeight(
          trailingCorrectCount(book.reviews, word.id),
        );
        final index = seenIndex[word.id];
        if (index == null) return mastery * 1.6;
        final denominator = max(1, seen.length - 1);
        final position = index / denominator;
        return mastery * (1.20 - (position * .75));
      },
    );
  }

  List<VocabWord> selectQuizWords(
    List<VocabWord> source,
    int requestedLimit,
    String modeKey, {
    bool wrongOnly = false,
  }) {
    final byId = <String, VocabWord>{
      for (final word in source) word.id: word,
    };
    final pool = byId.values.toList();
    if (pool.isEmpty) return [];

    final limit = requestedLimit.clamp(0, pool.length);
    if (limit == 0) return [];

    if (wrongOnly) {
      pool.shuffle();
      return pool.take(limit).toList();
    }

    final activeIds = wrongIds;
    final relearning =
        pool.where((word) => activeIds.contains(word.id)).toList()
          ..shuffle();

    final relearningCount = min(
      relearning.length,
      (limit * relearningShare).ceil(),
    );

    final relearningWords = relearning.take(relearningCount).toList();
    final selectedIds = relearningWords.map((word) => word.id).toSet();
    final normalPool =
        pool.where((word) => !activeIds.contains(word.id)).toList();

    final normalNeeded = limit - relearningWords.length;
    final balanced = modeKey == 'typing' || modeKey == 'meaning';

    final normalWords = balanced
        ? _balancedWords(modeKey, normalPool, normalNeeded)
        : weightedWordsWithoutReplacement(
            normalPool,
            normalNeeded,
            (word) => masterySelectionWeight(
              trailingCorrectCount(book.reviews, word.id),
            ),
          );

    selectedIds.addAll(normalWords.map((word) => word.id));

    final result = <VocabWord>[
      ...relearningWords,
      ...normalWords,
    ];

    if (result.length < limit) {
      final fill =
          pool.where((word) => !selectedIds.contains(word.id)).toList()
            ..shuffle();
      result.addAll(fill.take(limit - result.length));
    }

    result.shuffle();
    unawaited(_rememberQuizWords(modeKey, pool, result));
    return result;
  }

  Future<void> start() async {
    if (auth == null) {
      user = null;
      _authUid = null;
      await selectScope();
      return;
    }

    user = auth!.currentUser;
    _authUid = user?.uid;

    if (user != null && preferences.getBool(_guestDirtyKey) == true) {
      await _mergeGuestIntoPersonalCloud();
    } else {
      await selectScope();
    }

    _authSubscription = auth!.authStateChanges().listen((next) {
      if (next?.uid == _authUid) return;

      final wasGuest = _authUid == null;
      _authUid = next?.uid;
      user = next;

      if (next != null &&
          wasGuest &&
          preferences.getBool(_guestDirtyKey) == true) {
        unawaited(_mergeGuestIntoPersonalCloud());
      } else {
        unawaited(selectScope());
      }
    });
  }

  Future<void> selectScope(
    [String? group], {
    bool forceRemote = false,
  }) async {
    final generation = ++_generation;
    groupId = user == null ? null : group;

    busy = true;
    loaded = false;
    error = null;
    notifyListeners();

    try {
      if (user == null) {
        final repository = GuestRepository(preferences);
        _repository = repository;
        book = await repository.load();
        loaded = true;
        return;
      }

      if (firestore == null) {
        throw StateError('Firebase Firestore가 초기화되지 않았습니다.');
      }

      final cached =
          forceRemote ? null : _readCloudCache(user!.uid, groupId);

      final repository = CloudRepository(
        firestore!,
        user!.uid,
        groupId: groupId,
      );
      _repository = repository;

      if (cached != null) {
        book = cached;
        loaded = true;
        return;
      }

      final next = await repository.load();
      if (generation != _generation) return;

      book = next;
      loaded = true;
      await _writeCloudCache(user!.uid, groupId, next);
    } catch (exception) {
      if (generation == _generation) {
        error = '불러오지 못했습니다. 다시 시도해주세요. ($exception)';
      }
    } finally {
      if (generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshScope() => selectScope(
        groupId,
        forceRemote: true,
      );

  Future<void> _mergeGuestIntoPersonalCloud() async {
    final currentUser = user;

    if (currentUser == null || firestore == null) {
      await selectScope();
      return;
    }

    final generation = ++_generation;
    groupId = null;
    busy = true;
    loaded = false;
    error = null;
    notifyListeners();

    try {
      final guestRepository = GuestRepository(preferences);
      final guest = await guestRepository.load();
      final cloud = CloudRepository(firestore!, currentUser.uid);

      await cloud.mergeGuestNotebook(guest);
      final merged = await cloud.load();

      if (generation != _generation) return;

      _repository = cloud;
      book = merged;
      loaded = true;

      await _writeCloudCache(currentUser.uid, null, merged);
      await preferences.setBool(_guestDirtyKey, false);
    } catch (exception) {
      if (generation == _generation) {
        error = '로그아웃 중 저장한 단어를 클라우드와 병합하지 못했습니다. ($exception)';
      }
    } finally {
      if (generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _mutate(
    Future<void> Function(NotebookRepository repository) write,
    Notebook Function() next,
  ) async {
    if (busy || !loaded) {
      throw StateError('단어장을 먼저 불러오세요.');
    }

    final generation = _generation;
    busy = true;
    error = null;
    notifyListeners();

    try {
      await write(_repository!);
      if (generation != _generation) return;

      book = next();

      if (user == null) {
        await preferences.setBool(_guestDirtyKey, true);
      } else {
        await _writeCloudCache(user!.uid, groupId, book);
      }
    } catch (exception) {
      if (generation == _generation) {
        error = '저장하지 못했습니다. 다시 시도해주세요. ($exception)';
      }
      rethrow;
    } finally {
      if (generation == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> save(VocabWord word) => _mutate(
        (repository) => repository.putWord(word),
        () => book.replace(
          words: [
            ...book.words.where((candidate) => candidate.id != word.id),
            word,
          ],
        ),
      );

  Future<void> delete(String id) => _mutate(
        (repository) => repository.deleteWord(id),
        () => book.replace(
          words: book.words.where((word) => word.id != id).toList(),
        ),
      );

  Future<void> grade(VocabWord word, bool correct) {
    final now = DateTime.now();
    final nextWord = word.schedule(correct, now);

    final review = <String, dynamic>{
      'id': const Uuid().v4(),
      'date': dateKey(now),
      'wordId': word.id,
      'correct': correct,
    };

    return _mutate(
      (repository) => repository.review(nextWord, review),
      () => book.replace(
        words: book.words
            .map((candidate) => candidate.id == word.id ? nextWord : candidate)
            .toList(),
        reviews: [...book.reviews, review],
      ),
    );
  }

  Future<void> categories(List<String> values) {
    final clean = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return _mutate(
      (repository) => repository.setCategories(clean),
      () => book.replace(categories: clean),
    );
  }

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
    if (auth == null) {
      throw StateError('Firebase Auth가 초기화되지 않았습니다.');
    }

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
    if (auth == null) {
      throw StateError('Firebase Auth가 초기화되지 않았습니다.');
    }

    final provider = GoogleAuthProvider();

    if (kIsWeb) {
      await auth!.signInWithPopup(provider);
      return;
    }

    const clientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
    const serverId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

    _googleInitialization ??= GoogleSignIn.instance.initialize(
      clientId: clientId.isEmpty ? null : clientId,
      serverClientId: serverId.isEmpty ? null : serverId,
    );

    await _googleInitialization;

    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;

    if (token == null) {
      throw StateError('Google 인증 토큰을 받지 못했습니다.');
    }

    await auth!.signInWithCredential(
      GoogleAuthProvider.credential(idToken: token),
    );
  }

  Future<void> signOut() async {
    if (auth == null) return;

    try {
      if (!kIsWeb) await GoogleSignIn.instance.signOut();
    } catch (_) {}

    await auth!.signOut();
  }

  Future<String> createGroup(String name) async {
    if (user == null || firestore == null) {
      throw StateError('로그인이 필요합니다.');
    }

    final uid = user!.uid;
    final ref = firestore!.collection('groups').doc();

    await ref.set({
      'name': name.trim(),
      'ownerUid': uid,
      'memberUids': {uid: true},
      'memberEmails': {uid: user!.email ?? ''},
      'version': 1,
      'categories': <String>[],
      'reviewStorageVersion': 3,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await selectScope(ref.id, forceRemote: true);
    return ref.id;
  }

  Future<void> addMember(String memberUid) async {
    if (user == null || firestore == null || groupId == null) {
      throw StateError('그룹 단어장이 열려 있지 않습니다.');
    }

    await firestore!.collection('groups').doc(groupId).update({
      'memberUids.${memberUid.trim()}': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
