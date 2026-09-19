import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../domain/vocabulary.dart';

class CsvTransfer {
  Future<List<VocabWord>> importWords() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null) return [];
    final text = utf8
        .decode(result.files.single.bytes!)
        .replaceFirst('\uFEFF', '');
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(text);
    if (rows.isEmpty) throw const FormatException('CSV가 비어 있습니다.');
    final headers = rows.first.map((e) => e.toString().trim()).toList();
    if (!headers.contains('word') || !headers.contains('meaning')) {
      throw const FormatException('word, meaning 열이 필요합니다.');
    }
    return rows
        .skip(1)
        .where((row) => row.any((e) => e.toString().trim().isNotEmpty))
        .map((row) {
          final values = <String, dynamic>{
            for (var i = 0; i < headers.length; i++)
              headers[i]: i < row.length ? row[i].toString().trim() : '',
          };
          if (values['word'].isEmpty || values['meaning'].isEmpty) {
            throw const FormatException('단어와 뜻이 없는 행이 있습니다.');
          }
          final base = VocabWord.create(values['word'], values['meaning']);
          final data = <String, dynamic>{...base.data};
          for (final key in [
            'word',
            'meaning',
            'example',
            'translation',
            'synonyms',
            'memo',
            'category',
          ]) {
            if (values.containsKey(key)) data[key] = values[key];
          }
          data['favorite'] = values['favorite'] == 'true';
          for (final key in ['level', 'due', 'created']) {
            final parsed = int.tryParse(values[key] ?? '');
            if (parsed != null) {
              data[key] = key == 'level' ? parsed.clamp(0, 6) : parsed;
            }
          }
          for (final entry in {
            'examples_json': 'examples',
            'synonyms_json': 'synonymEntries',
            'meanings_json': 'meaningEntries',
          }.entries) {
            if ((values[entry.key] ?? '').isNotEmpty) {
              final decoded = jsonDecode(values[entry.key]);
              if (decoded is! List) {
                throw const FormatException('CSV의 확장 필드가 올바르지 않습니다.');
              }
              if (entry.value == 'examples') {
                if (decoded.any(
                  (e) =>
                      e is! Map ||
                      e['text'] is! String ||
                      e['translation'] is! String,
                )) {
                  throw const FormatException('예문 데이터가 올바르지 않습니다.');
                }
              } else if (decoded.any((e) => e is! String)) {
                throw const FormatException('뜻/유의어 데이터가 올바르지 않습니다.');
              }
              data[entry.value] = decoded;
            }
          }
          if (data['meaningEntries'] is List &&
              (data['meaningEntries'] as List).isNotEmpty) {
            data['meaning'] = (data['meaningEntries'] as List).join('; ');
          }
          return VocabWord(data);
        })
        .toList();
  }

  Future<void> exportWords(List<VocabWord> words) async {
    final headers = [
      'word',
      'meaning',
      'example',
      'translation',
      'synonyms',
      'memo',
      'category',
      'favorite',
      'level',
      'due',
      'created',
      'examples_json',
      'synonyms_json',
      'meanings_json',
    ];
    String safe(Object? value) {
      final text = value?.toString() ?? '';
      return RegExp(r'^[=+@\-\t\r]').hasMatch(text) ? "'$text" : text;
    }

    final rows = words.map((w) {
      final map = {
        ...w.data,
        'examples_json': jsonEncode(
          w.data['examples'] ??
              [
                {
                  'text': w.text('example'),
                  'translation': w.text('translation'),
                },
              ],
        ),
        'synonyms_json': jsonEncode(
          w.data['synonymEntries'] ??
              w
                  .text('synonyms')
                  .split(',')
                  .where((s) => s.trim().isNotEmpty)
                  .toList(),
        ),
        'meanings_json': jsonEncode(w.meanings),
      };
      return headers.map((h) => safe(map[h])).toList();
    });
    final text =
        '\uFEFF${const ListToCsvConverter().convert([headers, ...rows])}';
    await FilePicker.platform.saveFile(
      dialogTitle: '단어장 내보내기',
      fileName: 'leafy-${dateKey(DateTime.now())}.csv',
      bytes: Uint8List.fromList(utf8.encode(text)),
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
  }
}
