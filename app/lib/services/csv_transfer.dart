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

    final bytes = result.files.single.bytes;
    if (bytes == null) {
      throw const FormatException('CSV 파일을 읽지 못했습니다.');
    }

    final text = utf8
        .decode(bytes)
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(text);

    if (rows.isEmpty) {
      throw const FormatException('CSV가 비어 있습니다.');
    }

    const aliases = <String, String>{
      '카테고리': 'category',
      '분류': 'category',
      'category': 'category',
      '단어': 'word',
      '영단어': 'word',
      '영어단어': 'word',
      'word': 'word',
      '뜻': 'meaning',
      '의미': 'meaning',
      'meaning': 'meaning',
      '예문': 'example',
      '예시': 'example',
      'example': 'example',
      '예문의 의미': 'translation',
      '예문의 뜻': 'translation',
      '예문 뜻': 'translation',
      '예문해석': 'translation',
      'translation': 'translation',
      '메모': 'memo',
      'memo': 'memo',
      '유의어': 'synonyms',
      '동의어': 'synonyms',
      'synonyms': 'synonyms',
      'favorite': 'favorite',
      'level': 'level',
      'due': 'due',
      'created': 'created',
      'examples_json': 'examples_json',
      'synonyms_json': 'synonyms_json',
      'meanings_json': 'meanings_json',
    };

    String normalizeHeader(Object? value) {
      final raw = value?.toString().trim() ?? '';
      final lower = raw.toLowerCase();
      return aliases[raw] ?? aliases[lower] ?? lower;
    }

    final headers = rows.first.map(normalizeHeader).toList();

    if (!headers.contains('word') || !headers.contains('meaning')) {
      throw const FormatException(
        'CSV 헤더에 단어와 뜻이 필요합니다.\n'
        '권장 형식: 카테고리,단어,뜻,예문,예문의 의미,메모',
      );
    }

    final words = <VocabWord>[];

    for (final row in rows.skip(1)) {
      if (!row.any((value) => value.toString().trim().isNotEmpty)) {
        continue;
      }

      final values = <String, String>{
        for (var index = 0; index < headers.length; index++)
          headers[index]: index < row.length
              ? row[index].toString().trim()
              : '',
      };

      final wordText = values['word'] ?? '';
      final meaning = values['meaning'] ?? '';

      // 웹과 동일하게 필수값이 없는 행은 건너뛴다.
      if (wordText.isEmpty || meaning.isEmpty) {
        continue;
      }

      final base = VocabWord.create(wordText, meaning);
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
        final value = values[key];
        if (value != null) data[key] = value;
      }

      final favorite = values['favorite'];
      if (favorite != null && favorite.isNotEmpty) {
        data['favorite'] = favorite.toLowerCase() == 'true';
      }

      for (final key in ['level', 'due', 'created']) {
        final parsed = int.tryParse(values[key] ?? '');
        if (parsed == null) continue;

        data[key] = key == 'level'
            ? parsed.clamp(0, 6).toInt()
            : parsed;
      }

      for (final entry in {
        'examples_json': 'examples',
        'synonyms_json': 'synonymEntries',
        'meanings_json': 'meaningEntries',
      }.entries) {
        final encoded = values[entry.key] ?? '';
        if (encoded.isEmpty) continue;

        final decoded = jsonDecode(encoded);
        if (decoded is! List) {
          throw const FormatException('CSV의 확장 필드가 올바르지 않습니다.');
        }

        if (entry.value == 'examples') {
          if (decoded.any(
            (value) =>
                value is! Map ||
                value['text'] is! String ||
                value['translation'] is! String,
          )) {
            throw const FormatException('예문 데이터가 올바르지 않습니다.');
          }
        } else if (decoded.any((value) => value is! String)) {
          throw const FormatException('뜻/유의어 데이터가 올바르지 않습니다.');
        }

        data[entry.value] = decoded;
      }

      if (data['meaningEntries'] is! List ||
          (data['meaningEntries'] as List).isEmpty) {
        data['meaningEntries'] = <String>[meaning];
      } else {
        data['meaning'] = (data['meaningEntries'] as List).join('; ');
      }

      final example = '${data['example'] ?? ''}'.trim();
      final translation = '${data['translation'] ?? ''}'.trim();

      if ((data['examples'] is! List ||
              (data['examples'] as List).isEmpty) &&
          (example.isNotEmpty || translation.isNotEmpty)) {
        data['examples'] = <Map<String, String>>[
          {
            'text': example,
            'translation': translation,
          },
        ];
      }

      words.add(VocabWord(data));
    }

    if (words.isEmpty) {
      throw const FormatException('가져올 단어가 없습니다.');
    }

    return words;
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
