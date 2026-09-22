import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../domain/quiz_logic.dart';
import '../domain/vocabulary.dart';
import '../services/pronunciation.dart';
import '../state/leafy_controller.dart';
import 'app_theme.dart';

enum QuizMode { flash, choice, typing, meaning, context }

class _QuizUiController extends GetxController {
  int index = 0;
  int correctCount = 0;
  bool revealed = false;
  bool saving = false;
  bool? result;
  List<MeaningStudyItem> meaningItems = const [];
  final Set<String> completedMeaningKeys = <String>{};
  final Set<String> hintMeaningKeys = <String>{};
  String meaningMessage = '';

  void mutate(VoidCallback action) {
    action();
    update();
  }
}

const modeNames = {
  QuizMode.flash: '플래시카드',
  QuizMode.choice: '객관식 퀴즈',
  QuizMode.typing: '철자 입력',
  QuizMode.meaning: '의미 입력',
  QuizMode.context: '예문 퀴즈',
};

const modeIcons = {
  QuizMode.flash: Icons.layers_outlined,
  QuizMode.choice: Icons.quiz_outlined,
  QuizMode.typing: Icons.edit_outlined,
  QuizMode.meaning: Icons.menu_book_outlined,
  QuizMode.context: Icons.format_quote_outlined,
};

class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.controller,
    required this.words,
    required this.mode,
  });

  final LeafyController controller;
  final List<VocabWord> words;
  final QuizMode mode;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final input = TextEditingController();
  final speech = Pronunciation();

  final _ui = _QuizUiController();

  int get index => _ui.index;
  set index(int value) => _ui.index = value;
  int get correctCount => _ui.correctCount;
  set correctCount(int value) => _ui.correctCount = value;
  bool get revealed => _ui.revealed;
  set revealed(bool value) => _ui.revealed = value;
  bool get saving => _ui.saving;
  set saving(bool value) => _ui.saving = value;
  bool? get result => _ui.result;
  set result(bool? value) => _ui.result = value;

  late final String? uid = widget.controller.user?.uid;
  late final String? scope = widget.controller.groupId;

  List<MeaningStudyItem> get meaningItems => _ui.meaningItems;
  set meaningItems(List<MeaningStudyItem> value) => _ui.meaningItems = value;
  Set<String> get completedMeaningKeys => _ui.completedMeaningKeys;
  Set<String> get hintMeaningKeys => _ui.hintMeaningKeys;
  String get meaningMessage => _ui.meaningMessage;
  set meaningMessage(String value) => _ui.meaningMessage = value;

  late final List<List<String>> options = widget.words.map((word) {
    final target = word.meanings.isEmpty ? word.meaning : word.meanings.first;
    final alternatives = widget.controller.book.words
        .where((candidate) => candidate.id != word.id)
        .expand((candidate) => candidate.meanings)
        .map((meaning) => meaning.trim())
        .where((meaning) => meaning.isNotEmpty && meaning != target)
        .toSet()
        .toList()
      ..shuffle();

    return <String>[target, ...alternatives.take(3)]..shuffle();
  }).toList();

  VocabWord get currentWord => widget.words[index];

  @override
  void initState() {
    super.initState();
    _prepareQuestion();
  }


  void _prepareQuestion() {
    input.clear();
    revealed = false;
    result = null;
    meaningMessage = '';
    completedMeaningKeys.clear();
    hintMeaningKeys.clear();

    meaningItems = index < widget.words.length && widget.mode == QuizMode.meaning
        ? buildMeaningStudyItems(widget.words[index].meanings)
        : const [];
  }

  @override
  void dispose() {
    input.dispose();
    speech.stop();
    super.dispose();
  }

  Future<void> speak(VocabWord word) async {
    try {
      await speech.speak(word.word, widget.controller.accent);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<void> grade(bool correct) async {
    if (saving || result != null) return;

    _ui.mutate(() => saving = true);

    try {
      await widget.controller.grade(currentWord, correct);
      if (!mounted) return;

      _ui.mutate(() {
        result = correct;
        revealed = true;
        if (correct) correctCount++;
      });

      if (widget.controller.autoSpeak) {
        await speak(currentWord);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('채점 결과를 저장하지 못했습니다. $error')),
      );
    } finally {
      if (mounted) _ui.mutate(() => saving = false);
    }
  }

  Future<void> _submitMeaning() async {
    if (saving || result != null) return;

    final answer = input.text.trim();
    if (answer.isEmpty) return;

    final match = matchMeaningFragments(
      answer,
      meaningItems,
      completedMeaningKeys,
    );

    if (!match.valid) {
      _ui.mutate(() {
        meaningMessage = '남아 있는 의미나 표현과 일치하지 않아요.';
        input.clear();
      });
      return;
    }

    if (match.duplicateOnly) {
      _ui.mutate(() {
        meaningMessage = '이미 맞힌 표현이에요. 다른 표현을 떠올려보세요.';
        input.clear();
      });
      return;
    }

    _ui.mutate(() {
      completedMeaningKeys.addAll(match.matched.map((item) => item.key));
      meaningMessage =
          '${match.matched.map((item) => item.label).join(', ')} · 기억했어요.';
      input.clear();
    });

    if (completedMeaningKeys.length >= meaningItems.length) {
      await grade(true);
    }
  }

  void _showNextHint() {
    for (final item in meaningItems) {
      if (completedMeaningKeys.contains(item.key)) continue;
      if (hintMeaningKeys.contains(item.key)) continue;
      _ui.mutate(() => hintMeaningKeys.add(item.key));
      return;
    }
  }

  Widget _autoSpeakSetting() => Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 390),
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            color: LeafyTheme.surfaceSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.volume_up_outlined,
                size: 17,
                color: LeafyTheme.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '정답 확인 후 자동 발음',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '정답 확인 뒤 현재 단어를 들려줘요.',
                      style: TextStyle(fontSize: 9, color: LeafyTheme.muted),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: .75,
                child: Switch(
                  value: widget.controller.autoSpeak,
                  onChanged: (value) async {
                    await widget.controller.setAutoSpeak(value);
                    if (mounted) _ui.mutate(() {});
                  },
                ),
              ),
            ],
          ),
        ),
      );

  Widget _questionCard() {
    final word = currentWord;

    String title;
    String eyebrow;

    if (widget.mode == QuizMode.typing) {
      title = word.meanings.isEmpty ? word.meaning : word.meanings.first;
      eyebrow = '의미를 보고 영어 단어를 입력하세요';
    } else if (widget.mode == QuizMode.context) {
      final example = word.examples.firstOrNull?['text'] ?? '';
      title = maskExactWord(example, word.word) ?? example;
      eyebrow = '빈칸에 들어갈 단어를 입력하세요';
    } else if (widget.mode == QuizMode.meaning) {
      title = word.word;
      eyebrow = '기억나는 의미와 표현을 하나씩 입력하세요';
    } else {
      title = word.word;
      eyebrow = widget.mode == QuizMode.choice
          ? '가장 알맞은 의미를 고르세요'
          : '단어를 떠올린 뒤 정답을 확인하세요';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
        child: Column(
          children: [
            Text(
              eyebrow,
              style: const TextStyle(
                color: LeafyTheme.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: LeafyTheme.text,
                    height: 1.25,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            if ((widget.mode != QuizMode.typing &&
                    widget.mode != QuizMode.context) ||
                result != null)
              IconButton.filledTonal(
                onPressed: () => speak(word),
                tooltip: '영어 발음 듣기',
                icon: const Icon(Icons.volume_up_rounded),
              ),
            const SizedBox(height: 16),
            if (result == null) _answerArea(word),
            if (saving)
              const Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(),
              ),
            if (result != null) _feedback(word),
          ],
        ),
      ),
    );
  }

  Widget _answerArea(VocabWord word) {
    switch (widget.mode) {
      case QuizMode.flash:
        return _flashArea(word);
      case QuizMode.choice:
        return _choiceArea(word);
      case QuizMode.typing:
      case QuizMode.context:
        return _typingArea(word);
      case QuizMode.meaning:
        return _meaningArea(word);
    }
  }

  Widget _flashArea(VocabWord word) {
    if (!revealed) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _ui.mutate(() => revealed = true),
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('정답 보기'),
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: LeafyTheme.surfaceSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (final meaning in word.meanings)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(meaning, textAlign: TextAlign.center),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: saving ? null : () => grade(false),
                child: const Text('다시 볼게요'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: saving ? null : () => grade(true),
                child: const Text('기억했어요'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _choiceArea(VocabWord word) {
    final target = word.meanings.isEmpty ? word.meaning : word.meanings.first;

    return Column(
      children: [
        for (final choice in options[index])
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: saving ? null : () => grade(choice == target),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                ),
                child: Text(choice),
              ),
            ),
          ),
      ],
    );
  }

  Widget _typingArea(VocabWord word) => Column(
        children: [
          TextField(
            controller: input,
            enabled: !saving,
            autofocus: true,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitTypedAnswer(word),
            decoration: InputDecoration(
              labelText: widget.mode == QuizMode.context
                  ? '빈칸에 들어갈 단어'
                  : '영어 단어 입력',
              prefixIcon: const Icon(Icons.keyboard_outlined),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: saving ? null : () => _submitTypedAnswer(word),
              child: const Text('정답 확인'),
            ),
          ),
        ],
      );

  void _submitTypedAnswer(VocabWord word) {
    final answer = input.text.trim();
    if (answer.isNotEmpty) grade(acceptsSpelling(answer, word.word));
  }

  Widget _meaningArea(VocabWord word) {
    final visibleHints = meaningItems
        .where((item) =>
            hintMeaningKeys.contains(item.key) &&
            !completedMeaningKeys.contains(item.key))
        .toList();

    final nextHintExists = meaningItems.any((item) =>
        !completedMeaningKeys.contains(item.key) &&
        !hintMeaningKeys.contains(item.key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${completedMeaningKeys.length} / ${meaningItems.length}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: LeafyTheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '암기 항목 완료',
              style: TextStyle(color: LeafyTheme.muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 7,
            value: meaningItems.isEmpty
                ? 0
                : completedMeaningKeys.length / meaningItems.length,
            backgroundColor: LeafyTheme.surfaceSoft,
          ),
        ),
        if (completedMeaningKeys.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: meaningItems
                .where((item) => completedMeaningKeys.contains(item.key))
                .map((item) => Chip(
                      avatar: const Icon(Icons.check_rounded, size: 14),
                      label: Text(item.label),
                    ))
                .toList(),
          ),
        ],
        if (visibleHints.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final item in visibleHints)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xfffff8e9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '힌트 · ${makeMeaningHint(item.raw)}',
                style: const TextStyle(
                  color: LeafyTheme.warning,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
        ],
        const SizedBox(height: 14),
        TextField(
          controller: input,
          enabled: !saving,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitMeaning(),
          decoration: InputDecoration(
            labelText: '기억나는 표현',
            prefixIcon: const Icon(
              Icons.edit_note_rounded,
            ),
            suffixIcon: Tooltip(
              triggerMode: TooltipTriggerMode.tap,
              preferBelow: false,
              showDuration: const Duration(seconds: 8),
              message:
                  '괄호 안 설명은 입력하지 않아도 돼요.\n'
                  '쉼표, 세미콜론 또는 · 로 등록한 표현은 하나씩 맞힐 수 있어요.\n'
                  '힌트 사용은 오답 처리되지 않아요.',
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(
                  Icons.help_outline_rounded,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
        if (meaningMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            meaningMessage,
            style: const TextStyle(fontSize: 12, color: LeafyTheme.muted),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: saving ? null : _submitMeaning,
          child: const Text('이 표현 확인'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: saving || !nextHintExists ? null : _showNextHint,
                child: Text(
                  nextHintExists
                      ? hintMeaningKeys.isEmpty
                          ? '힌트 보기'
                          : '힌트 하나 더'
                      : '힌트 확인 완료',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton(
                onPressed: saving ? null : () => grade(false),
                child: const Text('모르겠어요 · 정답 보기'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _feedback(VocabWord word) {
    final missing = meaningItems
        .where((item) => !completedMeaningKeys.contains(item.key))
        .toList();

    return Column(
      children: [
        const Divider(height: 30),
        Icon(
          result == true ? Icons.check_circle_rounded : Icons.refresh_rounded,
          color: result == true ? LeafyTheme.primary : LeafyTheme.warning,
          size: 30,
        ),
        const SizedBox(height: 8),
        Text(
          widget.mode == QuizMode.meaning
              ? result == true
                  ? '등록한 모든 의미와 표현을 기억했어요!'
                  : '아직 외우지 못한 표현이 있어요.'
              : result == true
                  ? '잘 기억했어요!'
                  : '다음에 한 번 더 만나봐요.',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
          textAlign: TextAlign.center,
        ),
        if (widget.mode == QuizMode.meaning) ...[
          const SizedBox(height: 5),
          Text(
            '이번에 직접 맞힌 항목: ${completedMeaningKeys.length} / ${meaningItems.length}',
            style: const TextStyle(color: LeafyTheme.muted, fontSize: 12),
          ),
          if (result == false && missing.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '맞추지 못한 정답: ${missing.map((item) => item.label).join(', ')}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: LeafyTheme.warning,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
        _detailsCard(word),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: saving ? null : _next,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(index + 1 == widget.words.length ? '결과 보기' : '다음 단어'),
          ),
        ),
      ],
    );
  }

  Widget _detailsCard(VocabWord word) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 18, bottom: 16),
        decoration: BoxDecoration(
          color: LeafyTheme.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: LeafyTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: [
                  const Text(
                    '단어 정보',
                    style: TextStyle(
                      color: LeafyTheme.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    word.word,
                    style: const TextStyle(
                      color: LeafyTheme.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            _detailSection(
              '전체 의미',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final meaning in word.meanings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(meaning),
                    ),
                ],
              ),
            ),
            if (word.examples.isNotEmpty)
              _detailSection(
                '예문',
                Column(
                  children: [
                    for (final example in word.examples)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 7),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: LeafyTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((example['text'] ?? '').isNotEmpty)
                              Text(
                                example['text']!,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            if ((example['translation'] ?? '').isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                example['translation']!,
                                style: const TextStyle(
                                  color: LeafyTheme.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (word.synonymEntries.isNotEmpty)
              _detailSection(
                '유의어',
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: word.synonymEntries
                      .map((value) => Chip(label: Text(value)))
                      .toList(),
                ),
              ),
            if (word.text('memo').trim().isNotEmpty)
              _detailSection('메모', Text(word.text('memo')), last: true),
          ],
        ),
      );

  Widget _detailSection(
    String label,
    Widget child, {
    bool last = false,
  }) =>
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          border: last
              ? null
              : const Border(top: BorderSide(color: LeafyTheme.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: LeafyTheme.muted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );

  void _next() {
    speech.stop();
    _ui.mutate(() {
      index++;
      if (index < widget.words.length) _prepareQuestion();
    });
  }

  Future<void> _showQuizSettings() async {
    final total = widget.words.length;
    final current = index >= total ? total : index + 1;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => GetBuilder<LeafyController>(
        init: widget.controller,
        global: false,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(modeIcons[widget.mode]),
                  title: Text(
                    '${modeNames[widget.mode]} ($current/$total)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: const Text('현재 퀴즈 진행 상태'),
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(
                    Icons.volume_up_outlined,
                  ),
                  title: const Text(
                    '정답 확인 후 자동 발음',
                  ),
                  subtitle: const Text(
                    '정답 확인 뒤 현재 단어를 자동으로 읽어줘요.',
                  ),
                  value: widget.controller.autoSpeak,
                  onChanged: (value) async {
                    await widget.controller.setAutoSpeak(value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<LeafyController>(
      init: widget.controller,
      global: false,
      builder: (_) => GetBuilder<_QuizUiController>(
        init: _ui,
        global: false,
        builder: (_) {
          final identityChanged =
              widget.controller.user?.uid != uid ||
              widget.controller.groupId != scope;
          if (identityChanged) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            });
          }

          final done = index >= widget.words.length;

          return Scaffold(
      appBar: AppBar(
        title: Text(modeNames[widget.mode]!),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Text(
                done
                    ? '${widget.words.length}/${widget.words.length}'
                    : '${index + 1}/${widget.words.length}',
                style: const TextStyle(
                  color: LeafyTheme.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '퀴즈 설정',
            onPressed: _showQuizSettings,
            icon: const Icon(
              Icons.settings_outlined,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 54),
              children: [
                if (done) _resultPage(),
                if (!done) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 7,
                      value: (index + 1) / widget.words.length,
                      backgroundColor: LeafyTheme.surfaceSoft,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _questionCard(),
                ],
              ],
            ),
          ),
        ),
      ),
          );
        },
      ),
    );
  }

  Widget _resultPage() {
    final accuracy = widget.words.isEmpty
        ? 0
        : (correctCount / widget.words.length * 100).round();

    return Padding(
      padding: const EdgeInsets.only(top: 54),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(
              color: LeafyTheme.surfaceSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.eco_rounded,
              size: 42,
              color: LeafyTheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '오늘도 한 걸음 자랐어요.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.words.length}개 중 $correctCount개 정답 · 정답률 $accuracy%',
            style: const TextStyle(color: LeafyTheme.muted),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('학습 완료'),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
