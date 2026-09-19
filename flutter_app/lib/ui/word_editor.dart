import 'package:flutter/material.dart';
import '../domain/vocabulary.dart';

Future<VocabWord?> editWord(BuildContext context, {VocabWord? word}) =>
    showDialog<VocabWord>(
      context: context,
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
    for (final key in [
      'word',
      'meaning',
      'category',
      'example',
      'translation',
      'synonyms',
      'memo',
    ])
      key: TextEditingController(text: widget.word?.text(key) ?? ''),
  };
  @override
  void dispose() {
    for (final value in fields.values) {
      value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.word == null ? '새 단어' : '단어 수정'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in {
                'word': '영어 단어',
                'meaning': '뜻 (여러 뜻은 ; 로 구분)',
                'category': '카테고리',
                'example': '예문',
                'translation': '예문 해석',
                'synonyms': '유의어',
                'memo': '메모',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextFormField(
                    controller: fields[entry.key],
                    decoration: InputDecoration(labelText: entry.value),
                    maxLines: entry.key == 'memo' ? 3 : 1,
                    validator: (v) =>
                        ['word', 'meaning'].contains(entry.key) &&
                            (v ?? '').trim().isEmpty
                        ? '입력해주세요.'
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          final original = widget.word ?? VocabWord.create('', '');
          final data = {
            for (final entry in fields.entries)
              entry.key: entry.value.text.trim(),
          };
          final meanings = data['meaning']!
              .split(';')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          final changes = <String, dynamic>{
            ...data,
            'meaning': meanings.join('; '),
            'meaningEntries': meanings,
          };
          // Editing basic fields must not discard additional imported examples.
          if (data['example'] != original.text('example') ||
              data['translation'] != original.text('translation')) {
            changes['examples'] = [
              if (data['example']!.isNotEmpty ||
                  data['translation']!.isNotEmpty)
                {'text': data['example'], 'translation': data['translation']},
              ...((original.data['examples'] as List? ?? []).skip(1)),
            ];
          }
          if (data['synonyms'] != original.text('synonyms')) {
            changes['synonymEntries'] = data['synonyms']!
                .split(RegExp('[,;]'))
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
          Navigator.pop(context, original.copy(changes));
        },
        child: const Text('저장'),
      ),
    ],
  );
}
