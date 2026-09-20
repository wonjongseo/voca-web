import 'dart:math';
import 'vocabulary.dart';

const int relearningStreakTarget = 3;
const double relearningShare = .30;

class RelearningProgress {
  const RelearningProgress({
    required this.active,
    required this.wrong,
    required this.correct,
    required this.total,
    required this.streak,
    required this.accuracy,
    required this.lastWrong,
  });
  final bool active;
  final int wrong, correct, total, streak, accuracy;
  final String lastWrong;
}

RelearningProgress relearningProgress(
  List<Map<String, dynamic>> reviews,
  String wordId,
) {
  final history = reviews.where((review) => review['wordId'] == wordId).toList();
  final wrongReviews = history.where((review) => review['correct'] != true).toList();
  var trailingCorrect = 0;
  for (var index = history.length - 1; index >= 0; index--) {
    if (history[index]['correct'] != true) break;
    trailingCorrect++;
  }
  final wrong = wrongReviews.length;
  final correct = history.length - wrong;
  return RelearningProgress(
    active: wrong > 0 && trailingCorrect < relearningStreakTarget,
    wrong: wrong,
    correct: correct,
    total: history.length,
    streak: min(trailingCorrect, relearningStreakTarget),
    accuracy: history.isEmpty ? 0 : (correct / history.length * 100).round(),
    lastWrong: wrongReviews.isEmpty ? '' : '${wrongReviews.last['date'] ?? ''}',
  );
}

int trailingCorrectCount(List<Map<String, dynamic>> reviews, String wordId) {
  var streak = 0;
  for (var index = reviews.length - 1; index >= 0; index--) {
    final review = reviews[index];
    if (review['wordId'] != wordId) continue;
    if (review['correct'] != true) break;
    streak++;
  }
  return streak;
}

double masterySelectionWeight(int streak) {
  if (streak <= 0) return 1;
  if (streak <= 2) return .85;
  if (streak <= 4) return .55;
  if (streak <= 7) return .25;
  return .10;
}

List<VocabWord> weightedWordsWithoutReplacement(
  List<VocabWord> pool,
  int limit,
  double Function(VocabWord word) weightFor,
) {
  if (limit <= 0 || pool.isEmpty) return [];
  final random = Random();
  final scored = pool.map((word) {
    final weight = max(.0001, weightFor(word));
    final draw = max(double.minPositive, random.nextDouble());
    return (word: word, score: -log(draw) / weight);
  }).toList()
    ..sort((a, b) => a.score.compareTo(b.score));
  return scored.take(min(limit, scored.length)).map((entry) => entry.word).toList();
}

bool acceptsSpelling(String answer, String expected) {
  final a = answer.trim().toLowerCase();
  final b = expected.trim().toLowerCase();
  if (a == b) return true;
  if ((a.length - b.length).abs() > 1) return false;
  if (a.length == b.length) {
    final differences = <int>[];
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) differences.add(index);
    }
    return differences.length == 1 ||
        (differences.length == 2 &&
            differences[1] == differences[0] + 1 &&
            a[differences[0]] == b[differences[1]] &&
            a[differences[1]] == b[differences[0]]);
  }
  final shorter = a.length < b.length ? a : b;
  final longer = a.length < b.length ? b : a;
  var shortIndex = 0, longIndex = 0;
  var skipped = false;
  while (shortIndex < shorter.length && longIndex < longer.length) {
    if (shorter[shortIndex] == longer[longIndex]) {
      shortIndex++;
      longIndex++;
      continue;
    }
    if (skipped) return false;
    skipped = true;
    longIndex++;
  }
  return true;
}

String? maskExactWord(String text, String word) {
  if (text.trim().isEmpty || word.trim().isEmpty) return null;
  final escaped = RegExp.escape(word.trim());
  final matcher = RegExp(
    '(^|[^A-Za-z])($escaped)(?=\$|[^A-Za-z])',
    caseSensitive: false,
  );
  if (!matcher.hasMatch(text)) return null;
  return text.replaceFirstMapped(matcher, (match) => '${match.group(1) ?? ''}_____');
}

bool hasMaskableExample(VocabWord word) {
  final example = word.examples.isEmpty ? '' : word.examples.first['text'] ?? '';
  return maskExactWord(example, word.word) != null;
}

class MeaningStudyItem {
  const MeaningStudyItem({
    required this.key,
    required this.label,
    required this.normalized,
    required this.raw,
  });
  final String key, label, normalized, raw;
}

String removeMeaningContext(String value) => value
    .replaceAll(RegExp(r'[\u200B-\u200D\u2060\uFEFF]'), '')
    .replaceAll(RegExp(r'[~～〜]'), '')
    .replaceAll(RegExp(r'\([^)]*\)'), ' ')
    .replaceAll(RegExp(r'（[^）]*）'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String normalizeMeaningFragment(String value) =>
    removeMeaningContext(value).replaceAll(RegExp(r'\s+'), '').toLowerCase();

List<String> splitMeaningPartsOutsideParentheses(String value) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var roundDepth = 0, fullWidthDepth = 0;
  void push() {
    final text = buffer.toString().trim();
    if (text.isNotEmpty) parts.add(text);
    buffer.clear();
  }

  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (char == '(') {
      roundDepth++;
      buffer.write(char);
      continue;
    }
    if (char == ')') {
      if (roundDepth > 0) roundDepth--;
      buffer.write(char);
      continue;
    }
    if (char == '（') {
      fullWidthDepth++;
      buffer.write(char);
      continue;
    }
    if (char == '）') {
      if (fullWidthDepth > 0) fullWidthDepth--;
      buffer.write(char);
      continue;
    }
    final delimiter = char == ',' || char == '，' || char == '·' || char == 'ㆍ';
    if (delimiter && roundDepth == 0 && fullWidthDepth == 0) {
      push();
      continue;
    }
    buffer.write(char);
  }
  push();
  return parts;
}

List<MeaningStudyItem> buildMeaningStudyItems(List<String> meanings) {
  final result = <MeaningStudyItem>[];
  for (var meaningIndex = 0; meaningIndex < meanings.length; meaningIndex++) {
    final rawParts = splitMeaningPartsOutsideParentheses(meanings[meaningIndex]);
    for (var partIndex = 0; partIndex < rawParts.length; partIndex++) {
      final raw = rawParts[partIndex];
      final label = removeMeaningContext(raw);
      if (label.isEmpty) continue;
      result.add(MeaningStudyItem(
        key: '$meaningIndex:$partIndex',
        label: label,
        normalized: normalizeMeaningFragment(label),
        raw: raw,
      ));
    }
  }
  return result;
}

class MeaningMatch {
  const MeaningMatch({
    required this.valid,
    required this.matched,
    required this.duplicateOnly,
  });
  final bool valid, duplicateOnly;
  final List<MeaningStudyItem> matched;
}

MeaningMatch matchMeaningFragments(
  String answer,
  List<MeaningStudyItem> items,
  Set<String> completedKeys,
) {
  final answerParts = splitMeaningPartsOutsideParentheses(answer)
      .map(normalizeMeaningFragment)
      .where((part) => part.isNotEmpty)
      .toList();
  if (answerParts.isEmpty) {
    return const MeaningMatch(valid: false, matched: [], duplicateOnly: false);
  }
  final remaining = items.where((item) => !completedKeys.contains(item.key)).toList();
  final completed = items.where((item) => completedKeys.contains(item.key)).toList();
  final matched = <MeaningStudyItem>[];
  for (final answerPart in answerParts) {
    final pendingIndex =
        remaining.indexWhere((item) => item.normalized == answerPart);
    if (pendingIndex >= 0) {
      matched.add(remaining.removeAt(pendingIndex));
      continue;
    }
    if (completed.any((item) => item.normalized == answerPart)) continue;
    return const MeaningMatch(valid: false, matched: [], duplicateOnly: false);
  }
  return MeaningMatch(valid: true, matched: matched, duplicateOnly: matched.isEmpty);
}

String _maskToken(String token) {
  final cleaned = token.replaceAll(RegExp(r'[~～〜]'), '');
  final chars = cleaned.runes.map(String.fromCharCode).toList();
  if (chars.length <= 1) return cleaned;
  final buffer = StringBuffer(chars.first);
  final hideable = RegExp(r'[A-Za-z0-9가-힣ㄱ-ㅎㅏ-ㅣ]');
  for (final char in chars.skip(1)) {
    buffer.write(hideable.hasMatch(char) ? '○' : char);
  }
  return buffer.toString();
}

String makeMeaningHint(String value) {
  final output = StringBuffer();
  final normal = StringBuffer();
  var roundDepth = 0, fullWidthDepth = 0;
  void flushNormal() {
    final text = normal.toString();
    normal.clear();
    output.write(text.replaceAllMapped(
      RegExp(r'[^\s]+'),
      (match) => _maskToken(match.group(0)!),
    ));
  }

  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (char == '(' || char == '（') {
      flushNormal();
      if (char == '(') {
        roundDepth++;
      } else {
        fullWidthDepth++;
      }
      output.write(char);
      continue;
    }
    if (char == ')' || char == '）') {
      output.write(char);
      if (char == ')' && roundDepth > 0) roundDepth--;
      if (char == '）' && fullWidthDepth > 0) fullWidthDepth--;
      continue;
    }
    if (roundDepth > 0 || fullWidthDepth > 0) {
      output.write(char);
    } else {
      normal.write(char);
    }
  }
  flushNormal();
  return output.toString();
}
