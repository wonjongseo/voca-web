import 'package:flutter_tts/flutter_tts.dart';

class Pronunciation {
  final FlutterTts _tts = FlutterTts();
  Future<void> speak(String text, String locale) async {
    await _tts.stop();
    final voices = await _tts.getVoices;
    final matches = (voices as List)
        .where(
          (v) =>
              v['locale'].toString().replaceAll('_', '-').toLowerCase() ==
              locale.toLowerCase(),
        )
        .toList();
    if (matches.isEmpty) {
      throw StateError('선택한 영어 음성이 없습니다. 기기에 미국/영국 영어 음성을 설치해주세요.');
    }
    await _tts.setLanguage(locale);
    await _tts.setVoice({
      'name': matches.first['name'].toString(),
      'locale': matches.first['locale'].toString(),
    });
    await _tts.setSpeechRate(0.45);
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
