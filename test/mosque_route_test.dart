import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:noor_quran/data/mosque_route.dart';

/// v12 mosques route: OSRM road route online, straight dashed line
/// offline. The parse test pins the REAL recorded OSRM response for
/// جامع الإيمان → جامع الزيتونة (Muadamiyah): 602 m by road,
/// 16 geometry points, OSRM duration 65.9 s (wrong — the app computes
/// walking time itself: 602 m / 5 km/h ≈ 7 min).
void main() {
  const iman = LatLng(33.4666772, 36.1994628);
  const zaytuna = LatLng(33.4632666, 36.1977430);

  Map<String, dynamic> fixture() {
    final body = File('test/fixtures/osrm_iman_zaytuna.json')
        .readAsStringSync();
    return jsonDecode(body) as Map<String, dynamic>;
  }

  test('parseOsrmRoute: the real recorded response', () {
    final route = parseOsrmRoute(fixture());
    expect(route, isNotNull);
    expect(route!.isRoad, isTrue);
    expect(route.distanceMeters, 602);
    expect(route.points, hasLength(16));
    // GeoJSON is [lon, lat]; the first point is the start (الإيمان).
    expect(route.points.first.latitude, closeTo(33.466589, 0.0001));
    expect(route.points.first.longitude, closeTo(36.19957, 0.0001));
    expect(route.points.last.latitude, closeTo(33.46335, 0.0001));
    expect(route.points.last.longitude, closeTo(36.197685, 0.0001));
    // Walking time is computed in-app, NOT from OSRM's duration
    // (the fixture's duration is 65.9 s for 602 m — nonsense).
    expect(route.walkingMinutes, 7);
    expect(route.label, '٦٠٢ م، حوالي ٧ دقائق مشي');
  });

  test('parseOsrmRoute: bad shapes return null', () {
    expect(parseOsrmRoute({}), isNull);
    expect(parseOsrmRoute({'code': 'NoRoute', 'routes': []}), isNull);
    expect(parseOsrmRoute({'code': 'Ok', 'routes': []}), isNull);
    expect(
      parseOsrmRoute({
        'code': 'Ok',
        'routes': [
          {'distance': 100}
        ],
      }),
      isNull,
    );
    expect(
      parseOsrmRoute({
        'code': 'Ok',
        'routes': [
          {
            'distance': 100,
            'geometry': {'coordinates': []},
          },
        ],
      }),
      isNull,
    );
  });

  test('fetchOsrmRoute: MockClient success + failure', () async {
    final body = File('test/fixtures/osrm_iman_zaytuna.json')
        .readAsStringSync();
    final ok = MockClient(
        (_) async => http.Response.bytes(utf8.encode(body), 200));
    final route = await fetchOsrmRoute(iman, zaytuna, client: ok);
    expect(route, isNotNull);
    expect(route!.distanceMeters, 602);

    // The request goes to the OSRM foot profile with lon,lat order.
    var requestedUrl = '';
    final spy = MockClient((request) async {
      requestedUrl = request.url.toString();
      return http.Response.bytes(utf8.encode(body), 200);
    });
    await fetchOsrmRoute(iman, zaytuna, client: spy);
    expect(
      requestedUrl,
      'https://router.project-osrm.org/route/v1/foot/'
      '36.1994628,33.4666772;36.197743,33.4632666'
      '?overview=full&geometries=geojson',
    );

    // Non-200 / exception -> null (the caller draws the straight
    // line instead).
    final failing = MockClient((_) async => http.Response('no', 500));
    expect(
        await fetchOsrmRoute(iman, zaytuna, client: failing), isNull);
    final throwing = MockClient((_) async => throw const SocketException('x'));
    expect(
        await fetchOsrmRoute(iman, zaytuna, client: throwing), isNull);
  });

  test('straightRoute: two points, straight label, no walking time', () {
    final route = straightRoute(iman, zaytuna, 500);
    expect(route.isRoad, isFalse);
    expect(route.points, [iman, zaytuna]);
    expect(route.label, '٥٠٠ م بخط مستقيم');
  });

  test('labels: km distances and minute plurals', () {
    expect(
      const MosqueRoute(
        points: [],
        distanceMeters: 2500,
        isRoad: true,
      ).label,
      '٢٫٥ كم، حوالي ٣٠ دقيقة مشي',
    );
    expect(
      const MosqueRoute(
        points: [],
        distanceMeters: 80,
        isRoad: true,
      ).label,
      '٨٠ م، حوالي دقيقة واحدة مشي',
    );
    expect(
      const MosqueRoute(
        points: [],
        distanceMeters: 170,
        isRoad: true,
      ).label,
      '١٧٠ م، حوالي دقيقتان مشي',
    );
    expect(
      const MosqueRoute(
        points: [],
        distanceMeters: 12500,
        isRoad: true,
      ).label,
      '١٣ كم، حوالي ١٥٠ دقيقة مشي',
    );
  });

  test('segmentBearing: north 0, east 90, south 180', () {
    const origin = LatLng(33.0, 36.0);
    expect(segmentBearing(origin, const LatLng(34.0, 36.0)),
        closeTo(0, 0.5));
    expect(segmentBearing(origin, const LatLng(33.0, 37.0)),
        closeTo(90, 0.5));
    expect(segmentBearing(origin, const LatLng(32.0, 36.0)),
        closeTo(180, 0.5));
  });
}
