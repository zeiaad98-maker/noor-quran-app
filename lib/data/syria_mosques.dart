import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

/// ALL mosques of Syria, bundled offline — so the user sees the nearest
/// mosque anywhere in Syria even with no internet.
///
/// Source: OpenStreetMap Syria extract (Geofabrik syria-261115.osm.pbf,
/// 2026-11-15), filtered locally for amenity=place_of_worship +
/// religion=muslim, plus building=mosque and name-based catches
/// (جامع/مسجد) where the religion tag is missing. Deduped within 50 m
/// (same place mapped as a node AND a way — the named one is kept).
/// Clearly-not-mosques excluded: 1 mis-tagged church ('كنيسة (مغلقة)')
/// and 25 مقامات (shrines). 13 place_of_worship relations were not
/// extracted (their buildings are normally mapped as ways too).
///
/// Asset: `assets/quran_data/syria_mosques.json` — 2,919 mosques
/// (1,837 named, 1,082 unnamed), compact triples [name, lat, lon]
/// with 5-decimal coordinates. Unnamed entries ship with an empty
/// name and display as 'مسجد'.
///
/// NOTE: the user's local "جامع عثمان" in Muadamiyah is NOT in
/// OpenStreetMap (only جامع عثمان بن عفان in القدم/داريا, ~4.3 km
/// away), so it cannot be bundled — do NOT invent it. If he sends
/// its exact location it can be added to the map by hand.
class SyriaMosque {
  /// OSM name, or '' when the mosque is unnamed in OSM.
  final String name;
  final double lat;
  final double lng;

  const SyriaMosque({required this.name, required this.lat, required this.lng});

  /// What the list shows: the real name, or 'مسجد' for unnamed ones.
  String get displayName => name.isEmpty ? 'مسجد' : name;
}

class SyriaMosques {
  static const String assetPath = 'assets/quran_data/syria_mosques.json';

  /// Maximum radius the screen shows (matches the old live search).
  static const double maxDistanceMeters = 8000;

  static List<SyriaMosque>? _cached;

  /// Loads the bundled file once (via rootBundle) and caches it.
  /// Throws if the asset is missing or unparsable — callers must fall
  /// back to the live Nominatim search in that case.
  static Future<List<SyriaMosque>> ensureLoaded() async {
    if (_cached != null) return _cached!;
    final raw = await rootBundle.loadString(assetPath);
    _cached = parseSyriaMosques(raw);
    return _cached!;
  }

  /// Pure parse of the bundled JSON (no asset loading, no network) —
  /// this is what the tests exercise against the real file.
  static List<SyriaMosque> parseSyriaMosques(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final list = decoded['mosques'] as List<dynamic>;
    return list.map((e) {
      final row = e as List<dynamic>;
      return SyriaMosque(
        name: (row[0] as String?) ?? '',
        lat: (row[1] as num).toDouble(),
        lng: (row[2] as num).toDouble(),
      );
    }).toList(growable: false);
  }

  /// Haversine distance in metres — pure Dart, no plugin, so the
  /// offline path (and its tests) never touch a platform channel.
  static double haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dp = p2 - p1;
    final dl = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * earthRadius * math.asin(math.sqrt(a));
  }

  /// Nearest mosques first, within [maxDistanceMeters] of
  /// ([userLat], [userLng]). Same entry shape the screen already uses
  /// ({name, lat, lng, distance} in metres) so the offline results
  /// merge directly with the Nominatim fallback.
  static List<Map<String, dynamic>> nearestWithin(
    List<SyriaMosque> all,
    double userLat,
    double userLng, {
    double maxDistanceMeters = maxDistanceMeters,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final m in all) {
      final dist = haversineMeters(userLat, userLng, m.lat, m.lng);
      if (dist <= maxDistanceMeters) {
        out.add({
          'name': m.displayName,
          'lat': m.lat,
          'lng': m.lng,
          'distance': dist,
        });
      }
    }
    out.sort((a, b) =>
        (a['distance'] as double).compareTo(b['distance'] as double));
    return out;
  }
}
