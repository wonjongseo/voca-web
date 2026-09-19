import 'package:flutter/material.dart';
import '../domain/vocabulary.dart';
import '../services/pronunciation.dart';
import '../state/leafy_controller.dart';

enum QuizMode { flash, choice, typing, meaning, context }

const modeNames = {
  QuizMode.flash: '플래시카드',
  QuizMode.choice: '뜻 고르기',
  QuizMode.typing: '영어 입력',
  QuizMode.meaning: '뜻 입력',
  QuizMode.context: '빈칸 채우기',
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
  int index = 0, correctCount = 0;
  bool revealed = false, saving = false;
  bool? result;
  late final uid = widget.controller.user?.uid;
  late final scope = widget.controller.groupId;
  late final options = widget.words.map((word) {
    final alternatives =
        widget.controller.book.words
            .where((w) => w.meaning != word.meaning)
            .map((w) => w.meaning)
            .toSet()
            .toList()
          ..shuffle();
    return [word.meaning, ...alternatives.take(3)]..shuffle();
  }).toList();
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_identityChanged);
  }

  void _identityChanged() {
    if (widget.controller.user?.uid != uid ||
        widget.controller.groupId != scope) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_identityChanged);
    input.dispose();
    speech.stop();
    super.dispose();
  }

  Future<void> speak(VocabWord word) async {
    try {
      await speech.speak(word.word, widget.controller.accent);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> grade(bool correct) async {
    if (saving || result != null) return;
    setState(() => saving = true);
    try {
      await widget.controller.grade(widget.words[index], correct);
      if (!mounted) return;
      setState(() {
        result = correct;
        if (correct) correctCount++;
      });
      if (widget.controller.autoSpeak) await speak(widget.words[index]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('채점 결과를 저장하지 못했습니다. 다시 시도하세요. $e')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = index >= widget.words.length;
    final word = done ? null : widget.words[index];
    final typing =
        widget.mode == QuizMode.typing ||
        widget.mode == QuizMode.meaning ||
        widget.mode == QuizMode.context;
    return Scaffold(
      appBar: AppBar(title: Text(modeNames[widget.mode]!)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (done) ...[
                const Icon(Icons.eco, size: 64, color: Color(0xff386b50)),
                const SizedBox(height: 24),
                Text(
                  '오늘도 한 걸음 자랐어요.',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                Text(
                  '${widget.words.length}개 중 $correctCount개 정답',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('학습 완료'),
                ),
              ] else ...[
                LinearProgressIndicator(value: index / widget.words.length),
                const SizedBox(height: 12),
                Text('${index + 1} / ${widget.words.length}'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('정답 확인 후 발음 자동 듣기'),
                  value: widget.controller.autoSpeak,
                  onChanged: (v) async {
                    await widget.controller.setAutoSpeak(v);
                    if (mounted) setState(() {});
                  },
                ),
                const SizedBox(height: 32),
                Text(
                  widget.mode == QuizMode.typing
                      ? word!.meaning
                      : widget.mode == QuizMode.context
                      ? word!
                            .text('example')
                            .replaceAll(
                              RegExp(
                                RegExp.escape(word.word),
                                caseSensitive: false,
                              ),
                              '______',
                            )
                      : word!.word,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (widget.mode != QuizMode.typing &&
                        widget.mode != QuizMode.context ||
                    result != null)
                  IconButton(
                    onPressed: () => speak(word),
                    tooltip: '영어 발음 듣기',
                    icon: const Icon(Icons.volume_up),
                  ),
                if (widget.mode == QuizMode.flash) ...[
                  if (!revealed)
                    OutlinedButton(
                      onPressed: () => setState(() => revealed = true),
                      child: const Text('정답 보기'),
                    ),
                  if (revealed) ...[
                    Text(word.meaning, textAlign: TextAlign.center),
                    Text(word.text('example'), textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: saving || result != null
                              ? null
                              : () => grade(false),
                          child: const Text('다시 볼래요'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: saving || result != null
                              ? null
                              : () => grade(true),
                          child: const Text('기억해요'),
                        ),
                      ],
                    ),
                  ],
                ],
                if (widget.mode == QuizMode.choice)
                  for (final choice in options[index])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton(
                        onPressed: saving || result != null
                            ? null
                            : () => grade(choice == word.meaning),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(choice),
                        ),
                      ),
                    ),
                if (typing) ...[
                  TextField(
                    controller: input,
                    enabled: !saving && result == null,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: '정답 입력'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: saving || result != null
                        ? null
                        : () {
                            final answer = input.text.trim().toLowerCase();
                            if (answer.isEmpty) return;
                            grade(
                              widget.mode == QuizMode.meaning
                                  ? word.meanings.any(
                                      (m) => m.trim().toLowerCase() == answer,
                                    )
                                  : word.word.toLowerCase() == answer,
                            );
                          },
                    child: const Text('정답 확인'),
                  ),
                ],
                if (saving) const Center(child: CircularProgressIndicator()),
                if (result != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    result! ? '정답이에요!' : '다시 기억해봐요.',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('${word.word} · ${word.meaning}'),
                  Text(word.text('example')),
                  Text(word.text('translation')),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : () {
                            speech.stop();
                            setState(() {
                              index++;
                              result = null;
                              revealed = false;
                              input.clear();
                            });
                          },
                    child: const Text('다음'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
