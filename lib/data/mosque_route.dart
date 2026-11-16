import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Mosque route (v12): tapping a mosque draws the way from the user's
/// GPS location to the mosque.
///
/// ONLINE: the road route from OSRM (free, no key, foot profile).
/// Walking time is computed IN THE APP (distance / 5 km/h) — OSRM's
/// own duration field is wrong (it returned 66 s for a 602 m walk,
/// verified live 2026-11-16).
///
/// OFFLINE (or OSRM fails): a straight dashed line with the
/// straight-line distance — labelled as such, never presented as a
/// road distance.
class MosqueRoute {
  final List<LatLng> points;
  final double distanceMeters;
  final bool isRoad;

  const MosqueRoute({
    required this.points,
    required this.distanceMeters,
    required this.isRoad,
  });

  /// Walking time at ~5 km/h, in whole minutes.
  int get walkingMinutes => (distanceMeters / 5000 * 60).round();

  /// The pill text: road → "٦٠٢ م، حوالي ٧ دقائق مشي";
  /// straight → "٥٠٠ م بخط مستقيم" (no walking time — it is not
  /// the road distance).
  String get label {
    final dist = _formatDistance(distanceMeters);
    if (!isRoad) return '$dist بخط مستقيم';
    final m = walkingMinutes;
    // Arabic plural: 1 دقيقة واحدة، 2 دقيقتان، 3–10 دقائق، 11+ دقيقة.
    final time = m <= 1
        ? 'دقيقة واحدة'
        : m == 2
            ? 'دقيقتان'
            : m <= 10
                ? '${_arabicDigits(m)} دقائق'
                : '${_arabicDigits(m)} دقيقة';
    return '$dist، حوالي $time مشي';
  }

  static String _formatDistance(double meters) {
    if (meters < 1000) return '${_arabicDigits(meters.round())} م';
    final km = meters / 1000;
    final text = km >= 10
        ? km.round().toString()
        : km.toStringAsFixed(1);
    return '${_arabicDigitsString(text)} كم';
  }

  static String _arabicDigits(int n) => _arabicDigitsString('$n');

  static String _arabicDigitsString(String s) {
    const digits = '٠١٢٣٤٥٦٧٨٩';
    return s.split('').map((c) {
      if (c == '.') return '٫';
      final d = int.tryParse(c);
      return d == null ? c : digits[d];
    }).join();
  }
}

/// Fetches the OSRM road route from [from] to [to].
/// Returns null on any failure (no network, non-200, bad shape) —
/// the caller falls back to the straight line.
Future<MosqueRoute?> fetchOsrmRoute(
  LatLng from,
  LatLng to, {
  http.Client? client,
}) async {
  final url = Uri.parse(
    'https://router.project-osrm.org/route/v1/foot/'
    '${from.longitude},${from.latitude};'
    '${to.longitude},${to.latitude}'
    '?overview=full&geometries=geojson',
  );
  final httpClient = client ?? http.Client();
  try {
    final res = await httpClient
        .get(url)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    return parseOsrmRoute(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  } catch (_) {
    return null;
  } finally {
    if (client == null) httpClient.close();
  }
}

/// Parses an OSRM `/route/v1/foot?...geometries=geojson` response
/// into a [MosqueRoute]. Pure — pinned by tests against the real
/// recorded response (الإيمان → الزيتونة, 602 m, 16 points).
/// Returns null when the response has no usable route.
MosqueRoute? parseOsrmRoute(Map<String, dynamic> json) {
  if (json['code'] != 'Ok') return null;
  final routes = json['routes'] as List<dynamic>?;
  if (routes == null || routes.isEmpty) return null;
  final route = routes[0] as Map<String, dynamic>;
  final distance = (route['distance'] as num?)?.toDouble();
  final geometry = route['geometry'] as Map<String, dynamic>?;
  final coords = geometry?['coordinates'] as List<dynamic>?;
  if (distance == null || coords == null || coords.isEmpty) return null;
  final points = <LatLng>[];
  for (final c in coords) {
    final pair = c as List<dynamic>;
    if (pair.length < 2) return null;
    points.add(LatLng(
      (pair[1] as num).toDouble(),
      (pair[0] as num).toDouble(),
    ));
  }
  return MosqueRoute(
    points: points,
    distanceMeters: distance,
    isRoad: true,
  );
}

/// Straight-line fallback: user → mosque, with the straight distance
/// (the caller passes the haversine distance it already computed).
MosqueRoute straightRoute(LatLng from, LatLng to, double straightMeters) {
  return MosqueRoute(
    points: [from, to],
    distanceMeters: straightMeters,
    isRoad: false,
  );
}

/// Bearing (degrees clockwise from north) of the segment from [a] to
/// [b] — used to rotate the arrowhead marker at the route's end.
double segmentBearing(LatLng a, LatLng b) {
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLon = (b.longitude - a.longitude) * math.pi / 180;
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}
