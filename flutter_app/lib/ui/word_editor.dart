import 'package:flutter/material.dart';

import '../domain/vocabulary.dart';
import 'app_theme.dart';

Future<VocabWord?> editWord(
  BuildContext context, {
  VocabWord? word,
}) =>
    showDialog<VocabWord>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _WordEditor(word: word),
    );

class _WordEditor extends StatefulWidget {
  const _WordEditor({this.word});
  final VocabWord? word;

  @override
  State<_WordEditor> createState() => _WordEditorState();
}

class _WordEditorState extends State<_WordEditor> {
  final form = GlobalKey<FormState>();

  late final fields = <String, TextEditingController>{
    'word': TextEditingController(text: widget.word?.word ?? ''),
    'meaning': TextEditingController(text: widget.word?.meanings.join('\n') ?? ''),
    'category': TextEditingController(text: widget.word?.category ?? ''),
    'example': TextEditingController(
      text: widget.word?.examples.firstOrNull?['text'] ?? '',
    ),
    'translation': TextEditingController(
      text: widget.word?.examples.firstOrNull?['translation'] ?? '',
    ),
    'synonyms': TextEditingController(
      text: widget.word?.synonymEntries.join(', ') ?? '',
    ),
    'memo': TextEditingController(text: widget.word?.text('memo') ?? ''),
  };

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: LeafyTheme.surfaceSoft,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(
                            Icons.edit_note_rounded,
                            color: LeafyTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.word == null ? '새 단어 추가' : '단어 수정',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: fields['word'],
                      autofocus: widget.word == null,
                      decoration: const InputDecoration(labelText: '영어 단어'),
                      validator: (value) =>
                          (value ?? '').trim().isEmpty ? '단어를 입력해주세요.' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: fields['meaning'],
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: '의미',
                        hintText: '큰 의미는 줄바꿈 / 같은 의미 표현은 쉼표 또는 ·',
                      ),
                      validator: (value) =>
                          (value ?? '').trim().isEmpty ? '의미를 입력해주세요.' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: fields['category'],
                      decoration: const InputDecoration(labelText: '카테고리'),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: fields['example'],
                      decoration: const InputDecoration(labelText: '예문'),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: fields['translation'],
                      decoration: const InputDecoration(labelText: '예문 해석'),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: fields['synonyms'],
                      decoration: const InputDecoration(
                        labelText: '유의어',
                        hintText: '쉼표로 구분',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: fields['memo'],
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(labelText: '메모'),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('취소'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _save,
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('저장'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  void _save() {
    if (!form.currentState!.validate()) return;

    final original = widget.word ?? VocabWord.create('', '');
    final meanings = fields['meaning']!
        .text
        .trim()
        .split(RegExp(r'[;\n]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    final example = fields['example']!.text.trim();
    final translation = fields['translation']!.text.trim();
    final synonyms = fields['synonyms']!
        .text
        .split(RegExp(r'[,;\n]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    final updated = original.copy({
      'word': fields['word']!.text.trim(),
      'meaning': meanings.join('; '),
      'meaningEntries': meanings,
      'category': fields['category']!.text.trim(),
      'example': example,
      'translation': translation,
      'examples': <Map<String, String>>[
        if (example.isNotEmpty || translation.isNotEmpty)
          {'text': example, 'translation': translation},
        ...original.examples.skip(1),
      ],
      'synonyms': synonyms.join(', '),
      'synonymEntries': synonyms,
      'memo': fields['memo']!.text.trim(),
    });

    Navigator.pop(context, updated);
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
