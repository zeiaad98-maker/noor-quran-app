import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class NearbyMosquesScreen extends StatefulWidget {
  final double lat;
  final double lng;
  final String cityName;

  const NearbyMosquesScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.cityName,
  });

  @override
  State<NearbyMosquesScreen> createState() => _NearbyMosquesScreenState();
}

/// First segment of a Nominatim display_name ("جامع العمري, ...").
/// Falls back to 'مسجد' when empty.
String mosqueNameFromDisplayName(String? displayName) {
  final name = (displayName ?? 'مسجد').split(',').first.trim();
  return name.isEmpty ? 'مسجد' : name;
}

/// True when the name actually names a mosque (contains جامع or مسجد).
/// Nominatim free-text search matches the query word anywhere in the
/// address, so a `q=مسجد` search also returns streets, church names
/// and entrances ("شارع البلدية", "الكنيسة الإنجيلية", ...) — those
/// must be dropped, not shown as mosques.
bool isMosqueName(String name) =>
    name.contains('جامع') || name.contains('مسجد');

/// Parses one Nominatim search response into mosque entries
/// ({name, lat, lng, distance} in metres from [userLat]/[userLng]).
/// Drops entries without coordinates and entries farther than 8 km.
/// When [requireMosqueWord] is true (the `q=مسجد` query), entries
/// whose name does not name a mosque are dropped too.
List<Map<String, dynamic>> parseNominatimMosques(
  List<dynamic> items,
  double userLat,
  double userLng, {
  bool requireMosqueWord = false,
}) {
  final out = <Map<String, dynamic>>[];
  for (final item in items) {
    final mLat = double.tryParse(item['lat']?.toString() ?? '');
    final mLng = double.tryParse(item['lon']?.toString() ?? '');
    if (mLat == null || mLng == null) continue;
    final name = mosqueNameFromDisplayName(item['display_name']?.toString());
    if (requireMosqueWord && !isMosqueName(name)) continue;
    final dist = Geolocator.distanceBetween(userLat, userLng, mLat, mLng);
    if (dist <= 8000) {
      out.add({'name': name, 'lat': mLat, 'lng': mLng, 'distance': dist});
    }
  }
  return out;
}

class _NearbyMosquesScreenState extends State<NearbyMosquesScreen> {
  final MapController _mapController = MapController();
  bool _isLoading = true;
  List<Map<String, dynamic>> _mosques = [];

  @override
  void initState() {
    super.initState();
    _fetchMosquesReliably();
  }

  Future<void> _fetchMosquesReliably() async {
    setState(() => _isLoading = true);
    final List<Map<String, dynamic>> results = [];
    final Set<String> seen = {};

    void addMosque(String name, double mLat, double mLng) {
      final key = '${mLat.toStringAsFixed(4)}_${mLng.toStringAsFixed(4)}';
      if (seen.contains(key)) return;
      seen.add(key);
      final dist = Geolocator.distanceBetween(widget.lat, widget.lng, mLat, mLng);
      if (dist <= 8000) {
        results.add({'name': name, 'lat': mLat, 'lng': mLng, 'distance': dist});
      }
    }

    // Nominatim OpenStreetMap (سريع وموثوق جداً عبر GET).
    //
    // WHY Arabic queries: the old `q=mosque` (English) is a free-text
    // name search — Syrian mosques are tagged with Arabic names, so it
    // returned exactly ONE mosque near Muadamiyah (جامع الزيتونة,
    // 2.8 km) while 22 named mosques sit within 8 km (verified live
    // 2026-11-16). `q=جامع` alone returns 18; `q=مسجد` adds 5 more
    // (after the name filter below). The old Overpass fallback is
    // REMOVED: all four public Overpass endpoints are unusable from
    // here (kumi: 25s+ timeout, api.de: HTTP 406 on GET and POST,
    // private.coffee: 30s timeout, nchc: unreachable) — it only ever
    // burned 10 s and delivered nothing.
    const queries = [('جامع', false), ('مسجد', true)];
    for (final (query, requireWord) in queries) {
      try {
        // Viewbox ±0.075° ≈ ±8 km, matching the 8 km distance filter.
        const delta = 0.075;
        final viewbox =
            '${widget.lng - delta},${widget.lat + delta},${widget.lng + delta},${widget.lat - delta}';
        final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&bounded=1&viewbox=$viewbox&limit=50&accept-language=ar',
        );
        final res = await http
            .get(url, headers: {
              'User-Agent': 'NoorQuranApp/1.0 (syria.noor.quran)'
            })
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final list = json.decode(utf8.decode(res.bodyBytes)) as List;
          for (final m in parseNominatimMosques(
            list,
            widget.lat,
            widget.lng,
            requireMosqueWord: requireWord,
          )) {
            addMosque(
              m['name'] as String,
              m['lat'] as double,
              m['lng'] as double,
            );
          }
        }
      } catch (_) {}
    }

    results.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

    if (mounted) {
      setState(() {
        _mosques = results;
        _isLoading = false;
      });
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} متر';
    return '${(meters / 1000).toStringAsFixed(1)} كم';
  }

  Future<void> _navigateToMosque(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    const emerald = Color(0xFF0C6E52);
    const gold = Color(0xFFB8934A);
    final userPoint = LatLng(widget.lat, widget.lng);

    return Scaffold(
      appBar: AppBar(
        title: Text('مساجد ${widget.cityName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location_rounded),
            onPressed: () => _mapController.move(userPoint, 15.0),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchMosquesReliably,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. الخريطة التفاعلية الحية داخل التطبيق نفسه
          SizedBox(
            height: 260,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: userPoint,
                initialZoom: 14.8,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.noor.quran',
                ),
                MarkerLayer(
                  markers: [
                    // دبوس موقع المستخدم الحالي (أزرق)
                    Marker(
                      point: userPoint,
                      width: 44,
                      height: 44,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(Icons.my_location_rounded, color: Colors.blue, size: 26),
                        ),
                      ),
                    ),
                    // دبابيس المساجد المكتشفة (خضراء)
                    ..._mosques.map((m) {
                      return Marker(
                        point: LatLng(m['lat'] as double, m['lng'] as double),
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${m['name']} (${_formatDistance(m['distance'])})'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: emerald,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.mosque_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),

          // 2. قائمة المساجد أسفل الخريطة
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: emerald))
                : _mosques.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('يمكنك تحريك الخريطة بالأعلى لاستكشاف منطقتك'),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _fetchMosquesReliably,
                              icon: const Icon(Icons.refresh),
                              label: const Text('تحديث القائمة'),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _mosques.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final m = _mosques[index];
                          final isNearest = index == 0;
                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: isNearest ? emerald : gold.withValues(alpha: 0.25)),
                            ),
                            child: ListTile(
                              onTap: () {
                                _mapController.move(LatLng(m['lat'], m['lng']), 16.5);
                              },
                              leading: CircleAvatar(
                                backgroundColor: isNearest ? emerald : gold.withValues(alpha: 0.18),
                                child: Icon(Icons.mosque_rounded, color: isNearest ? Colors.white : gold),
                              ),
                              title: Text(m['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('يبعد عنك: ${_formatDistance(m['distance'])} • اضغط لعرضه على الخريطة'),
                              trailing: IconButton(
                                icon: const Icon(Icons.directions_walk_rounded, color: emerald),
                                onPressed: () => _navigateToMosque(m['lat'], m['lng']),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
