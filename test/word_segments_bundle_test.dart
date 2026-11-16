import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/quran_audio.dart';
import 'package:noor_quran/data/word_meanings.dart';

/// Word-audio fix, round 2: the v9 index fix was correct, but word
/// audio still never sounded on the user's weak connection, because
/// every tap first waited on api.quran.com (15 s timeout, no cache)
/// and then streamed the whole 408 KB ayah file before a late word
/// could sound — with no timeout on setUrl and the error hidden
/// behind the modal sheet. The fix resolves segments offline-first
/// (bundled Husary asset, SharedPreferences cache for other
/// reciters) and time-boxes playback with a wbw fallback.
/// These tests pin the offline-first resolution; controller-level
/// playback itself still cannot run in a unit test — just_audio's
/// AudioPlayer needs a real audio platform (its own suite replaces
/// JustAudioPlatform with a ~500-line mock player, and a
/// method-channel mock hangs in setUrl). Real playback is verified
/// on the device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setBundledHusaryForTest(null);
  });

  test('bundled Husary segments: 2:33 matches the live API fixture', () async {
    final segments = await bundledWordSegments(2, 33);
    expect(segments, isNotNull);
    expect(segments!.length, 22);
    expect(segments[0].startMs, 850);
    expect(segments[0].endMs, 1760);
    expect(segments[1].startMs, 1770);
    expect(segments[1].endMs, 5010);
    expect(segments[21].startMs, 44650);
    expect(segments[21].endMs, 47580);
  });

  test('bundled Husary segments: spot counts match the morphology words',
      () async {
    expect((await bundledWordSegments(2, 25))!.length, 34);
    expect((await bundledWordSegments(2, 26))!.length, 39);
    expect((await bundledWordSegments(2, 255))!.length, 50);
    expect((await bundledWordSegments(1, 1))!.length, 4);
    expect((await bundledWordSegments(1, 1))![0].startMs, 50);
  });

  test('bundle integrity: 6218 ayahs, 77098 words, all well-formed',
      () async {
    final raw = await rootBundle
        .loadString('assets/quran_data/word_segments_husary.json');
    final bundle = jsonDecode(raw) as Map<String, dynamic>;
    expect(bundle.length, 6218);
    var words = 0;
    for (final entry in bundle.entries) {
      final segments = parseStoredSegments(entry.value as List<dynamic>);
      expect(segments, isNotNull, reason: 'malformed ${entry.key}');
      words += segments!.length;
    }
    expect(words, 77098);
  });

  test('bundle coverage: exactly the 18 gap ayahs are missing, '
      'and every present ayah matches the morphology word count',
      () async {
    const missing = {
      '3:73', '3:153', '6:165', '9:66', '9:94', '12:1', '13:31',
      '15:1', '17:95', '20:14', '20:98', '29:38', '34:30', '39:6',
      '45:34', '52:33', '65:7', '74:41',
    };
    // One known divergence: 37:130 — the API times «إِلْ يَاسِينَ»
    // as TWO audio words, the morphology dump as one, so the bundle
    // has 4 segments for 3 chips (chip 3 plays «إِلْ», next-word
    // reaches «يَاسِينَ» as word 4). Everything else lines up 1:1.
    const divergent = {'37:130'};
    var missingCount = 0;
    for (var surah = 1; surah <= 114; surah++) {
      for (var verse = 1; verse <= quran.getVerseCount(surah); verse++) {
        final segments = await bundledWordSegments(surah, verse);
        if (segments == null) {
          missingCount++;
          expect(missing.contains('$surah:$verse'), isTrue,
              reason: 'unexpected gap $surah:$verse');
          continue;
        }
        // Segment list must line up 1:1 with the Uthmani words the
        // sheet chips (and the wbw files) number by.
        final words = await QuranWordData.wordsForAyah(surah, verse);
        if (divergent.contains('$surah:$verse')) {
          expect(segments.length, 4);
          expect(words.length, 3);
          continue;
        }
        expect(segments.length, words.length,
            reason: 'count mismatch $surah:$verse');
      }
    }
    expect(missingCount, missing.length);
  });

  test('parseStoredSegments: rejects malformed pair lists', () {
    expect(parseStoredSegments([]), isNull);
    expect(parseStoredSegments([
      [100],
    ]), isNull);
    expect(parseStoredSegments([
      [500, 400],
    ]), isNull);
    // Starts going backwards are malformed.
    expect(
        parseStoredSegments([
          [200, 300],
          [100, 200],
        ]),
        isNull);
    // Overlapping but in order is fine: a merged breath is stored
    // once per word it covers (e.g. 2:125's [34280, 37290] twice).
    expect(
        parseStoredSegments([
          [0, 100],
          [50, 200],
        ]),
        isNotNull);
    expect(
        parseStoredSegments([
          [0, 100],
          [0, 100],
        ]),
        isNotNull);
    expect(
        parseStoredSegments([
          [0, 100],
          [100, 200],
        ]),
        isNotNull);
  });

  test('wordSegmentsFor: Husary never touches the network', () async {
    final husary = reciters.firstWhere((r) => r.name == 'محمود الحصري');
    var httpCalls = 0;
    final neverCall = MockClient((_) async {
      httpCalls++;
      return http.Response('must not be called', 500);
    });
    final segments = await http.runWithClient(
      () => wordSegmentsFor(husary, 2, 33),
      () => neverCall,
    );
    expect(httpCalls, 0);
    expect(segments, isNotNull);
    expect(segments!.length, 22);

    // A gap ayah (3:73, one of the 18 where the API skips a word
    // index) also stays offline: bundle miss -> null, no API
    // attempt for recitation 6.
    final gap = await http.runWithClient(
      () => wordSegmentsFor(husary, 3, 73),
      () => neverCall,
    );
    expect(httpCalls, 0);
    expect(gap, isNull);

    // And a merged-breath ayah (2:125) resolves offline too, with
    // the shared span expanded to one entry per word.
    final merged = await http.runWithClient(
      () => wordSegmentsFor(husary, 2, 125),
      () => neverCall,
    );
    expect(httpCalls, 0);
    expect(merged, isNotNull);
    expect(merged!.length, 22);
    expect(merged[16].startMs, 34280);
    expect(merged[16].endMs, 37290);
    expect(merged[17].startMs, 34280);
    expect(merged[17].endMs, 37290);
    expect(merged[18].startMs, 37300);
  });

  test('wordSegmentsFor: other reciters hit the API once, then the cache',
      () async {
    final afasy = reciters.firstWhere((r) => r.name == 'مشاري العفاسي');
    final body =
        File('test/fixtures/quran_com_2_33_husary.json').readAsStringSync();
    var httpCalls = 0;
    final mock = MockClient((request) async {
      httpCalls++;
      expect(request.url.host, 'api.quran.com');
      expect(request.url.queryParameters['audio'], '7');
      return http.Response.bytes(utf8.encode(body), 200);
    });

    final first = await http.runWithClient(
      () => wordSegmentsFor(afasy, 2, 33),
      () => mock,
    );
    expect(first, isNotNull);
    expect(first!.length, 22);
    expect(httpCalls, 1);
    // Cached in SharedPreferences now.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('word_segments_7_2:33'), isNotNull);

    // Second call: cache hit, zero HTTP even with a failing client.
    final neverCall = MockClient((_) async {
      httpCalls++;
      return http.Response('must not be called', 500);
    });
    final second = await http.runWithClient(
      () => wordSegmentsFor(afasy, 2, 33),
      () => neverCall,
    );
    expect(httpCalls, 1);
    expect(second, isNotNull);
    expect(second!.length, 22);
    expect(second[0].startMs, 850);
  });

  test('wordSegmentsFor: API failure -> null, nothing cached; '
      'reciter without segments never calls the API', () async {
    final afasy = reciters.firstWhere((r) => r.name == 'مشاري العفاسي');
    var httpCalls = 0;
    final failing = MockClient((_) async {
      httpCalls++;
      return http.Response('nope', 404);
    });
    final none = await http.runWithClient(
      () => wordSegmentsFor(afasy, 2, 33),
      () => failing,
    );
    expect(none, isNull);
    expect(httpCalls, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('word_segments_7_2:33'), isNull);

    final maher = reciters.firstWhere((r) => r.name == 'ماهر المعيقلي');
    final neverCall = MockClient((_) async {
      httpCalls++;
      return http.Response('must not be called', 500);
    });
    expect(
        await http.runWithClient(
          () => wordSegmentsFor(maher, 2, 33),
          () => neverCall,
        ),
        isNull);
    expect(httpCalls, 1);
  });

  test('setBundledHusaryForTest: injected bundle is used, reset restores',
      () async {
    setBundledHusaryForTest({
      '9:99': [
        [0, 100],
        [100, 200],
      ],
    });
    final injected = await bundledWordSegments(9, 99);
    expect(injected, isNotNull);
    expect(injected!.length, 2);
    setBundledHusaryForTest(null);
    final real = await bundledWordSegments(2, 33);
    expect(real, isNotNull);
    expect(real!.length, 22);
  });
}
