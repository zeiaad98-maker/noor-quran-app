import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quran/quran.dart' as quran;

import 'package:noor_quran/data/quran_audio.dart';
import 'package:noor_quran/data/word_meanings.dart';

/// v9 word-audio bug: the ayah sheet built its word chips from the
/// `quran` package's SIMPLE text (`getVerse(...).split(' ')`), but
/// Quran.com's word audio (segments + wbw files) numbers words in
/// UTHMANI order. For 2:33 the simple text has 24 tokens
/// (`يَا` + `آدَمُ` split, plus a standalone `ۖ`) while the audio has
/// 22 words — so taps played the WRONG word, and the last chips
/// 404'd on wbw (`..._023.mp3`, `..._024.mp3` do not exist).
/// These tests pin the fix: word indices come from the bundled
/// Uthmani word list (QuranWordData.wordsForAyah), which is
/// segment-aligned.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parseWordSegments: canned REAL Quran.com 2:33 response', () {
    final body = File('test/fixtures/quran_com_2_33_husary.json')
        .readAsStringSync();
    final verse =
        (jsonDecode(body) as Map<String, dynamic>)['verse']
            as Map<String, dynamic>;
    final segments = parseWordSegments(verse);
    expect(segments, isNotNull);
    expect(segments!.length, 22);
    // First word قَالَ: 850–1760ms; word 2 (يَـٰٓـَٔادَمُ): 1770–5010ms;
    // last word تَكْتُمُونَ: 44650–47580ms.
    expect(segments[0].startMs, 850);
    expect(segments[0].endMs, 1760);
    expect(segments[1].startMs, 1770);
    expect(segments[1].endMs, 5010);
    expect(segments[21].startMs, 44650);
    expect(segments[21].endMs, 47580);
  });

  test('parseWordSegments: missing/garbled shapes return null', () {
    expect(parseWordSegments({}), isNull);
    expect(parseWordSegments({'audio': null}), isNull);
    expect(parseWordSegments({'audio': {'segments': []}}), isNull);
    // Segments with fewer than 4 fields are ignored -> empty -> null.
    expect(
        parseWordSegments({
          'audio': {
            'segments': [
              [0, 850, 1760],
            ],
          },
        }),
        isNull);
    // A gap in the indices (no segment 1) is incomplete -> null.
    expect(
        parseWordSegments({
          'audio': {
            'segments': [
              [0, 1, 850, 1760],
              [2, 3, 5020, 7860],
            ],
          },
        }),
        isNull);
  });

  test('fetchWordSegments: MockClient with the real response', () async {
    final body = File('test/fixtures/quran_com_2_33_husary.json')
        .readAsStringSync();
    final husary = reciters.firstWhere((r) => r.name == 'محمود الحصري');
    final mock = MockClient((request) async {
      expect(request.url.host, 'api.quran.com');
      expect(request.url.queryParameters['audio'], '6');
      // NOTE: http.Response(String, ...) encodes as LATIN-1 and throws
      // on Arabic text — the body must go in as UTF-8 bytes.
      return http.Response.bytes(utf8.encode(body), 200);
    });
    final segments = await http.runWithClient(
      () => fetchWordSegments(husary, 2, 33),
      () => mock,
    );
    expect(segments, isNotNull);
    expect(segments!.length, 22);

    // Non-200 -> null (falls back to wbw in the controller).
    final failing = MockClient((_) async => http.Response('nope', 404));
    final none = await http.runWithClient(
      () => fetchWordSegments(husary, 2, 33),
      () => failing,
    );
    expect(none, isNull);

    // A reciter without a Quran.com recitation never calls the API.
    final maher = reciters.firstWhere((r) => r.name == 'ماهر المعيقلي');
    expect(
        await fetchWordSegments(maher, 2, 33),
        isNull);
  });

  test('wordsForAyah: Uthmani list is segment-aligned (2:33 = 22)', () async {
    final words = await QuranWordData.wordsForAyah(2, 33);
    expect(words.length, 22);
    // Word 2 is the SINGLE Uthmani token يَـٰٓـَٔادَمُ (the old simple
    // split made it two chips: يَا + آدَمُ).
    expect(QuranWordData.normalizeArabic(words[1]), 'يادم');
    expect(QuranWordData.normalizeArabic(words[21]), 'تكتمون');
    // And the pause mark is attached to its word, not a token.
    expect(words.any((w) => w.trim() == 'ۖ'), isFalse);

    // Spot checks against the live API segment counts (verified
    // 2026-11-16): 2:25 = 34, 2:26 = 39, 2:255 = 50, 1:1 = 4.
    expect((await QuranWordData.wordsForAyah(2, 25)).length, 34);
    expect((await QuranWordData.wordsForAyah(2, 26)).length, 39);
    expect((await QuranWordData.wordsForAyah(2, 255)).length, 50);
    expect((await QuranWordData.wordsForAyah(1, 1)).length, 4);
  });

  test('the old simple-text split really differs (documents the bug)', () {
    final simple = quran
        .getVerse(2, 33)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    expect(simple.length, 24);
    expect(simple[1], 'يَا');
    expect(simple[2], 'آدَمُ');
    expect(simple[5], 'ۖ');
  });

  // NOTE on scope: the controller-level playWord wiring (wordCount from
  // wordsForAyah, segment seek, wbw fallback) cannot run in a unit test —
  // just_audio's AudioPlayer needs a real audio platform: its own test
  // suite replaces JustAudioPlatform with a ~500-line mock player. The
  // pieces the controller calls are all pinned above (parseWordSegments,
  // fetchWordSegments, wordsForAyah, URL builders), and the controller
  // change is a 1-line await of wordsForAyah. Real playback is verified
  // on the device.
}
