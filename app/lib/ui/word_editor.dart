import 'package:flutter/material.dart';

import '../domain/vocabulary.dart';
import 'app_theme.dart';

Future<VocabWord?> editWord(
  BuildContext context, {
  VocabWord? word,
}) {
  return Navigator.of(context).push<VocabWord>(
    MaterialPageRoute(
      builder: (_) => WordEditorScreen(word: word),
    ),
  );
}

class WordEditorScreen extends StatefulWidget {
  const WordEditorScreen({super.key, this.word});

  final VocabWord? word;

  @override
  State<WordEditorScreen> createState() => _WordEditorScreenState();
}

class _WordEditorScreenState extends State<WordEditorScreen> {
  final form = GlobalKey<FormState>();

  late final fields = <String, TextEditingController>{
    'word': TextEditingController(text: widget.word?.word ?? ''),
    'meaning': TextEditingController(text: widget.word?.meanings.join('\n') ?? ''),
    'category': TextEditingController(text: widget.word?.category ?? ''),
    'example': TextEditingController(text: widget.word?.examples.firstOrNull?['text'] ?? ''),
    'translation': TextEditingController(text: widget.word?.examples.firstOrNull?['translation'] ?? ''),
    'synonyms': TextEditingController(text: widget.word?.synonymEntries.join(', ') ?? ''),
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
  Widget build(BuildContext context) {
    final editing = widget.word != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '단어 수정' : '새 단어 추가'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('저장', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: form,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.edit_note_rounded, color: Theme.of(context).colorScheme.primary, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        editing
                            ? '단어의 뜻, 예문, 유의어와 메모를 편하게 수정할 수 있어요.'
                            : '단어와 의미만 입력해도 저장할 수 있어요. 나머지는 필요할 때 추가하세요.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('기본 정보', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              TextFormField(
                controller: fields['word'],
                autofocus: !editing,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '영어 단어',
                  hintText: '예: provide',
                  prefixIcon: Icon(Icons.abc_rounded),
                ),
                validator: (value) => (value ?? '').trim().isEmpty ? '단어를 입력해주세요.' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: fields['meaning'],
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '의미',
                  hintText: '큰 의미는 줄바꿈 / 같은 의미 표현은 쉼표 또는 ·',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.translate_rounded),
                ),
                validator: (value) => (value ?? '').trim().isEmpty ? '의미를 입력해주세요.' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: fields['category'],
                decoration: const InputDecoration(
                  labelText: '카테고리',
                  hintText: '예: TOEIC 700',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
              ),
              const SizedBox(height: 24),
              const Text('예문', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              TextFormField(
                controller: fields['example'],
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '예문',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.format_quote_rounded),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: fields['translation'],
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '예문 해석',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.subtitles_outlined),
                ),
              ),
              const SizedBox(height: 24),
              const Text('추가 정보', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              TextFormField(
                controller: fields['synonyms'],
                decoration: const InputDecoration(
                  labelText: '유의어',
                  hintText: '쉼표로 구분',
                  prefixIcon: Icon(Icons.compare_arrows_rounded),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: fields['memo'],
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '메모',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _save,
                icon: Icon(Icons.check_rounded),
                label: Text(editing ? '수정 내용 저장' : '단어 저장'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
