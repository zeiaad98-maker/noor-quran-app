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

    // المحرك الأول: Nominatim OpenStreetMap (سريع وموثوق جداً عبر GET)
    try {
      final delta = 0.04; // نطاق ~4.5 كم حول المستخدم
      final viewbox = '${widget.lng - delta},${widget.lat + delta},${widget.lng + delta},${widget.lat - delta}';
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=mosque&format=json&bounded=1&viewbox=$viewbox&limit=50&accept-language=ar',
      );
      final res = await http.get(url, headers: {'User-Agent': 'NoorQuranApp/1.0 (syria.noor.quran)'}).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final list = json.decode(utf8.decode(res.bodyBytes)) as List;
        for (final item in list) {
          final mLat = double.tryParse(item['lat']?.toString() ?? '');
          final mLng = double.tryParse(item['lon']?.toString() ?? '');
          if (mLat != null && mLng != null) {
            final rawName = (item['display_name']?.toString() ?? 'مسجد').split(',').first.trim();
            addMosque(rawName.isEmpty ? 'مسجد' : rawName, mLat, mLng);
          }
        }
      }
    } catch (_) {}

    // المحرك الثاني: Overpass GET لتعزيز النتائج
    if (results.length < 5) {
      try {
        final q = '[out:json][timeout:10];(nwr["amenity"="place_of_worship"]["religion"="muslim"](around:4000,${widget.lat},${widget.lng});nwr["building"="mosque"](around:4000,${widget.lat},${widget.lng}););out center;';
        final url = Uri.parse('https://overpass.kumi.systems/api/interpreter?data=${Uri.encodeComponent(q)}');
        final res = await http.get(url, headers: {'User-Agent': 'NoorQuranApp/1.0'}).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final data = json.decode(utf8.decode(res.bodyBytes));
          final elements = (data['elements'] as List?) ?? [];
          for (final el in elements) {
            final double? mLat = (el['lat'] as num?)?.toDouble() ?? (el['center']?['lat'] as num?)?.toDouble();
            final double? mLng = (el['lon'] as num?)?.toDouble() ?? (el['center']?['lon'] as num?)?.toDouble();
            if (mLat != null && mLng != null) {
              final tags = (el['tags'] as Map?) ?? {};
              final name = tags['name:ar'] ?? tags['name'] ?? 'مسجد';
              addMosque(name.toString(), mLat, mLng);
            }
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
