import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noor_quran/data/syria_mosques.dart';

/// Offline bundled mosques of Syria (v12).
///
/// The bundled file is the REAL asset shipped in the app
/// (assets/quran_data/syria_mosques.json), built from the Geofabrik
/// Syria extract (syria-latest.osm.pbf, 2026-11-16) with maximal
/// extraction (place_of_worship + religion=muslim, building=mosque,
/// religion=muslim + building/name, name-based catches جامع/مسجد/مصلى,
/// place_of_worship relations) PLUS the GeoNames Syria dump (S.MSQE,
/// CC-BY 4.0) merged at 250 m. 3,057 mosques: 1,976 named, 1,081
/// unnamed.
///
/// These tests are OFFLINE-ONLY: parsing and the nearest query use
/// pure Dart (no HTTP, no platform channels) — nothing here touches
/// the network. Ground truths:
/// * جامع الإيمان, Muadamiyah — 33.4666772, 36.1994628 (user-verified)
/// * الجامع الأموي, Damascus — ~33.5118, 36.3068
/// * جامع الزيتونة, Muadamiyah — 33.46329, 36.19778
/// * جامع بلال, Daraa — 32.60882, 36.09061 (GeoNames-only entry)
void main() {
  late List<SyriaMosque> all;

  setUpAll(() {
    final raw =
        File('assets/quran_data/syria_mosques.json').readAsStringSync();
    all = SyriaMosques.parseSyriaMosques(raw);
  });

  SyriaMosque? findByName(String name) {
    for (final m in all) {
      if (m.name == name) return m;
    }
    return null;
  }

  group('bundled file', () {
    test('count and named/unnamed split', () {
      expect(all.length, 3057);
      final named = all.where((m) => m.name.isNotEmpty).length;
      expect(named, 1976);
      expect(all.length - named, 1081);
    });

    test('all coordinates are inside Syria', () {
      for (final m in all) {
        expect(m.lat, inInclusiveRange(32.0, 37.5));
        expect(m.lng, inInclusiveRange(35.0, 42.5));
      }
    });

    test('no church or shrine slipped in', () {
      for (final m in all) {
        expect(m.name.contains('كنيس'), isFalse);
        expect(m.name.startsWith('مقام'), isFalse);
      }
    });

    test('loads through rootBundle too (the path the app uses)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final loaded = await SyriaMosques.ensureLoaded();
      expect(loaded.length, 3057);
    });
  });

  group('spot checks', () {
    test('جامع الإيمان is at the ground-truth coordinates', () {
      final m = findByName('جامع الإيمان');
      expect(m, isNotNull);
      expect(
        SyriaMosques.haversineMeters(m!.lat, m.lng, 33.4666772, 36.1994628),
        lessThan(5),
      );
    });

    test('الجامع الأموي (Damascus) is within 100 m of the known point', () {
      final m = findByName('الجامع الأموي');
      expect(m, isNotNull);
      expect(
        SyriaMosques.haversineMeters(m!.lat, m.lng, 33.5118, 36.3068),
        lessThan(100),
      );
    });

    test('جامع الزيتونة (Muadamiyah) is present', () {
      final m = findByName('جامع الزيتونة');
      expect(m, isNotNull);
      expect(
        SyriaMosques.haversineMeters(m!.lat, m.lng, 33.46329, 36.19778),
        lessThan(100),
      );
    });

    test('GeoNames-only entry: جامع بلال (Daraa) is present', () {
      // GeoNames S.MSQE row, 1,043 m from the nearest OSM entry —
      // the bundle's only mosque in Daraa that OSM does not have.
      final nearDaraa = SyriaMosques.nearestWithin(all, 32.62, 36.10);
      expect(
        nearDaraa.any((e) =>
            e['name'] == 'جامع بلال' &&
            (e['distance'] as double) < 2000),
        isTrue,
      );
      // Daraa centre: 10 mosques within 8 km (was 9 in v11).
      expect(nearDaraa.length, 10);
    });

    test('the local جامع عثمان is NOT in OSM — only عثمان بن عفان '
        '(القدم/داريا) exists', () {
      // The user's neighbourhood mosque (~500 m from him, Muadamiyah)
      // is not mapped in OpenStreetMap, so it cannot be bundled.
      // Guard against anyone inventing it: no bare 'جامع عثمان'
      // within 8 km of his area — the only عثمان-named mosque there
      // is جامع عثمان بن عفان in القدم/داريا. (A bare 'جامع عثمان'
      // does exist elsewhere in Syria, e.g. Aleppo — that is a
      // different mosque, not his.)
      final nearUser = SyriaMosques.nearestWithin(all, 33.44, 36.186);
      final othmanNearUser =
          nearUser.where((m) => (m['name'] as String).contains('عثمان'));
      expect(othmanNearUser.map((m) => m['name']), ['جامع عثمان بن عفان']);
      final othman = findByName('جامع عثمان بن عفان');
      expect(othman, isNotNull);
      expect(
        SyriaMosques.haversineMeters(
            othman!.lat, othman.lng, 33.4651085, 36.2461506),
        lessThan(5),
      );
    });
  });

  group('nearestWithin', () {
    test('haversine sanity: الإيمان to الزيتونة is ~407 m', () {
      final d = SyriaMosques.haversineMeters(
          33.4666772, 36.1994628, 33.46329206, 36.1977844);
      expect(d, inInclusiveRange(380, 440));
      expect(SyriaMosques.haversineMeters(33.44, 36.186, 33.44, 36.186),
          0);
    });

    test('Muadamiyah near جامع الإيمان: الإيمان is nearest', () {
      final near =
          SyriaMosques.nearestWithin(all, 33.4667, 36.1995);
      expect(near, isNotEmpty);
      expect(near.first['name'], 'جامع الإيمان');
      expect(near.first['distance'] as double, lessThan(50));
      // Sorted nearest-first, all within 8 km.
      for (var i = 1; i < near.length; i++) {
        expect(near[i]['distance'] as double,
            greaterThanOrEqualTo(near[i - 1]['distance'] as double));
        expect(near[i]['distance'] as double, lessThanOrEqualTo(8000));
      }
      // Richer than the old live search: 22 named mosques in 8 km
      // via Nominatim, 59 total here (named + unnamed).
      expect(near.length, greaterThan(40));
    });

    test('central Damascus: الجامع الأموي is nearest', () {
      final near = SyriaMosques.nearestWithin(all, 33.5118, 36.3068);
      expect(near, isNotEmpty);
      expect(near.first['name'], 'الجامع الأموي');
      expect(near.first['distance'] as double, lessThan(100));
    });

    test('Aleppo citadel: nearest mosque within 100 m', () {
      final near = SyriaMosques.nearestWithin(all, 36.1992, 37.1626);
      expect(near, isNotEmpty);
      expect(near.first['distance'] as double, lessThan(100));
      expect((near.first['name'] as String).isNotEmpty, isTrue);
    });

    test('Homs centre: nearest mosque within 150 m', () {
      final near = SyriaMosques.nearestWithin(all, 34.7269, 36.7235);
      expect(near, isNotEmpty);
      expect(near.first['distance'] as double, lessThan(150));
    });

    test('far outside Syria returns nothing', () {
      expect(SyriaMosques.nearestWithin(all, 0, 0), isEmpty);
    });

    test('unnamed mosques display as مسجد', () {
      final unnamed = all.firstWhere((m) => m.name.isEmpty);
      expect(unnamed.displayName, 'مسجد');
      // And the nearest list carries that label, not an empty name.
      final near = SyriaMosques.nearestWithin(
          all, unnamed.lat, unnamed.lng);
      expect(near.first['name'], 'مسجد');
      expect(near.first['distance'] as double, lessThan(5));
    });
  });
}
