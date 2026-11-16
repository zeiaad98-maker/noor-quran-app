import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noor_quran/screens/nearby_mosques_screen.dart';

/// Nearby-mosques search, verified against REAL Nominatim responses
/// recorded 2026-11-16 around Muadamiyah al-Sham (user point
/// 33.44, 36.186 — his screenshot showed the map there).
///
/// The bug (v9): the app asked Nominatim `q=mosque` (English
/// free-text name search). Syrian mosques are tagged with Arabic
/// names, so it returned exactly ONE mosque (جامع الزيتونة, 2.8 km)
/// while 22 named mosques sit within 8 km. The fix queries
/// `q=جامع` + `q=مسجد` (with a name filter on the noisy مسجد
/// results) and drops the dead Overpass fallback (all four public
/// endpoints unusable: kumi 25s+ timeout, api.de HTTP 406,
/// private.coffee 30s timeout, nchc unreachable).
void main() {
  const userLat = 33.44;
  const userLng = 36.186;

  List<dynamic> loadFixture(String name) {
    final body =
        File('test/fixtures/$name').readAsStringSync();
    return jsonDecode(body) as List<dynamic>;
  }

  /// Same merge the screen does: dedupe by coordinate key (4 dp),
  /// keep the first entry per key.
  List<Map<String, dynamic>> merge(
      List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final m in [...a, ...b]) {
      final key =
          '${(m['lat'] as double).toStringAsFixed(4)}_${(m['lng'] as double).toStringAsFixed(4)}';
      if (seen.add(key)) out.add(m);
    }
    out.sort((x, y) =>
        (x['distance'] as double).compareTo(y['distance'] as double));
    return out;
  }

  group('mosqueNameFromDisplayName', () {
    test('takes the first segment', () {
      expect(
        mosqueNameFromDisplayName('جامع العمري, طريق القهوة القديمة, معضمية الشام'),
        'جامع العمري',
      );
    });

    test('empty or null falls back to مسجد', () {
      expect(mosqueNameFromDisplayName(''), 'مسجد');
      expect(mosqueNameFromDisplayName(null), 'مسجد');
      expect(mosqueNameFromDisplayName(', something'), 'مسجد');
    });
  });

  group('isMosqueName', () {
    test('accepts جامع / مسجد names', () {
      expect(isMosqueName('جامع العمري'), isTrue);
      expect(isMosqueName('مسجد الفضل بن العباس'), isTrue);
    });

    test('rejects streets, churches and entrances', () {
      expect(isMosqueName('شارع البلدية'), isFalse);
      expect(isMosqueName('الكنيسة الإنجيلية'), isFalse);
      expect(isMosqueName('مدخل جديدة عرطوز'), isFalse);
    });
  });

  group('parseNominatimMosques — real Muadamiyah responses', () {
    test('q=جامع: 18 entries, all named, all within 8 km', () {
      final parsed = parseNominatimMosques(
        loadFixture('nominatim_jamia_muadamiyah.json'),
        userLat,
        userLng,
      );
      expect(parsed.length, 18);
      for (final m in parsed) {
        expect(isMosqueName(m['name'] as String), isTrue,
            reason: m['name'] as String);
        expect(m['distance'] as double, lessThanOrEqualTo(8000));
      }
      final sorted = [...parsed]
        ..sort((a, b) => (a['distance'] as double)
            .compareTo(b['distance'] as double));
      expect(sorted.first['name'], 'جامع العادل');
      expect(sorted.first['distance'] as double, lessThan(1500));
    });

    test('q=مسجد unfiltered: 30 entries, including non-mosques', () {
      final parsed = parseNominatimMosques(
        loadFixture('nominatim_masjid_muadamiyah.json'),
        userLat,
        userLng,
      );
      expect(parsed.length, 30);
      // The noise the name filter exists for:
      expect(
        parsed.map((m) => m['name'] as String),
        contains('الكنيسة الإنجيلية'),
      );
      expect(
        parsed.map((m) => m['name'] as String),
        contains('شارع البلدية'),
      );
    });

    test('q=مسجد filtered: 22 entries, every one a real mosque', () {
      final parsed = parseNominatimMosques(
        loadFixture('nominatim_masjid_muadamiyah.json'),
        userLat,
        userLng,
        requireMosqueWord: true,
      );
      expect(parsed.length, 22);
      for (final m in parsed) {
        expect(isMosqueName(m['name'] as String), isTrue,
            reason: m['name'] as String);
        expect(m['distance'] as double, lessThanOrEqualTo(8000));
      }
    });

    test('old q=mosque query: exactly 1 mosque (the bug)', () {
      final parsed = parseNominatimMosques(
        loadFixture('nominatim_mosque_muadamiyah.json'),
        userLat,
        userLng,
      );
      expect(parsed.length, 1);
      expect(parsed.first['name'], 'جامع الزيتونة');
    });

    test('merged جامع + مسجد: 22 unique, nearest first', () {
      final jamia = parseNominatimMosques(
        loadFixture('nominatim_jamia_muadamiyah.json'),
        userLat,
        userLng,
      );
      final masjid = parseNominatimMosques(
        loadFixture('nominatim_masjid_muadamiyah.json'),
        userLat,
        userLng,
        requireMosqueWord: true,
      );
      final merged = merge(jamia, masjid);
      expect(merged.length, 22);
      // The أبو ذر / ابي ذر duplicate (same coordinates) collapses.
      expect(
        merged.where((m) => (m['name'] as String).contains('ذر')).length,
        1,
      );
      expect(merged.first['name'], 'جامع العادل');
      expect(merged.last['name'], 'مسجد الفضل بن العباس');
      for (var i = 1; i < merged.length; i++) {
        expect(
          merged[i]['distance'] as double,
          greaterThanOrEqualTo(merged[i - 1]['distance'] as double),
        );
      }
    });
  });
}
