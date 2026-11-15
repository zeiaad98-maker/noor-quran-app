import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
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
  int _selectedMosqueIndex = -1;

  @override
  void initState() {
    super.initState();
    _fetchMosquesInsideApp();
  }

  Future<void> _fetchMosquesInsideApp() async {
    setState(() => _isLoading = true);
    final List<Map<String, dynamic>> loaded = [];
    final Set<String> seen = {};

    void addMosque(String name, double mLat, double mLng) {
      final key = '${mLat.toStringAsFixed(4)}_${mLng.toStringAsFixed(4)}';
      if (seen.contains(key)) return;
      seen.add(key);
      final dist = Geolocator.distanceBetween(widget.lat, widget.lng, mLat, mLng);
      if (dist <= 8000) {
        loaded.add({
          'name': name.isEmpty ? 'مسجد' : name,
          'lat': mLat,
          'lng': mLng,
          'distance': dist,
        });
      }
    }

    // المحرك الأول: Photon OSM API (سريع جداً ولا يُحظر)
    try {
      final uri = Uri.parse(
        'https://photon.komoot.io/api/?q=مسجد&lat=${widget.lat}&lon=${widget.lng}&limit=25',
      );
      final res = await http.get(uri, headers: {'User-Agent': 'NoorQuranApp/1.0'}).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(utf8.decode(res.bodyBytes));
        for (final feat in (data['features'] as List? ?? [])) {
          final coords = feat['geometry']?['coordinates'] as List?;
          final props = feat['properties'] as Map? ?? {};
          if (coords != null && coords.length >= 2) {
            final mLng = (coords[0] as num).toDouble();
            final mLat = (coords[1] as num).toDouble();
            final name = (props['name'] ?? 'مسجد').toString();
            addMosque(name, mLat, mLng);
          }
        }
      }
    } catch (_) {}

    // المحرك الثاني الاحتياطي: Nominatim OSM Search
    if (loaded.length < 3) {
      try {
        final delta = 0.045;
        final viewbox = '${widget.lng - delta},${widget.lat + delta},${widget.lng + delta},${widget.lat - delta}';
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&q=mosque&bounded=1&viewbox=$viewbox&limit=25&accept-language=ar',
        );
        final res = await http.get(uri, headers: {'User-Agent': 'NoorQuranApp/1.0'}).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final list = json.decode(utf8.decode(res.bodyBytes)) as List;
          for (final item in list) {
            final mLat = double.tryParse(item['lat']?.toString() ?? '');
            final mLng = double.tryParse(item['lon']?.toString() ?? '');
            if (mLat != null && mLng != null) {
              final rawName = (item['display_name'] ?? 'مسجد').toString().split(',').first.trim();
              addMosque(rawName, mLat, mLng);
            }
          }
        }
      } catch (_) {}
    }

    loaded.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

    if (mounted) {
      setState(() {
        _mosques = loaded;
        _isLoading = false;
      });
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} متر';
    return '${(meters / 1000).toStringAsFixed(1)} كم';
  }

  Future<void> _navigateToMosque(double lat, double lng, String name) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      final fallback = Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(name)})');
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    const emerald = Color(0xFF0C6E52);
    const gold = Color(0xFFB8934A);
    final userPoint = LatLng(widget.lat, widget.lng);

    return Scaffold(
      appBar: AppBar(
        title: Text('المساجد القريبة (${widget.cityName})', style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location_rounded),
            tooltip: 'موقعي الحالي',
            onPressed: () => _mapController.move(userPoint, 15.0),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchMosquesInsideApp,
          ),
        ],
      ),
      body: Column(
        children: [
          // خريطة تفاعلية مدمجة داخل التطبيق
          SizedBox(
            height: 250,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: userPoint,
                initialZoom: 14.5,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.noor.quran',
                ),
                MarkerLayer(
                  markers: [
                    // دبوس موقعك الحالي
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
                          child: Icon(Icons.person_pin_circle_rounded, color: Colors.blue, size: 32),
                        ),
                      ),
                    ),
                    // دبابيس المساجد القريبة
                    ...List.generate(_mosques.length, (i) {
                      final m = _mosques[i];
                      final isSelected = i == _selectedMosqueIndex;
                      return Marker(
                        point: LatLng(m['lat'], m['lng']),
                        width: 44,
                        height: 44,
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedMosqueIndex = i),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected ? gold : emerald,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                            ),
                            child: const Icon(Icons.mosque_rounded, color: Colors.white, size: 22),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),

          // قائمة المساجد المرتبة من الأقرب للأبعد
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: emerald),
                        SizedBox(height: 10),
                        Text('جاري تحديد المساجد المحيطة بك...'),
                      ],
                    ),
                  )
                : _mosques.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.mosque_outlined, size: 48, color: gold),
                            const SizedBox(height: 8),
                            const Text('لم تظهر مساجد مسجلة في هذه المنطقة'),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _fetchMosquesInsideApp,
                              icon: const Icon(Icons.refresh),
                              label: const Text('تحديث البحث'),
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
                          final isSelected = index == _selectedMosqueIndex;

                          return Card(
                            elevation: isSelected ? 4 : 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: isSelected ? gold : (isNearest ? emerald : gold.withValues(alpha: 0.25)),
                                width: isSelected || isNearest ? 1.6 : 1,
                              ),
                            ),
                            child: ListTile(
                              onTap: () {
                                setState(() => _selectedMosqueIndex = index);
                                _mapController.move(LatLng(m['lat'], m['lng']), 16.5);
                              },
                              leading: CircleAvatar(
                                backgroundColor: isNearest ? emerald : gold.withValues(alpha: 0.18),
                                child: Icon(Icons.mosque_rounded, color: isNearest ? Colors.white : gold),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      m['name'],
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
                                    ),
                                  ),
                                  if (isNearest)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: emerald.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'الأقرب',
                                        style: TextStyle(fontSize: 11, color: emerald, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('المسافة: ${_formatDistance(m['distance'])}'),
                              ),
                              trailing: FilledButton.icon(
                                style: FilledButton.styleFrom(backgroundColor: emerald),
                                onPressed: () => _navigateToMosque(m['lat'], m['lng'], m['name']),
                                icon: const Icon(Icons.directions_walk_rounded, size: 16),
                                label: const Text('اتجاه'),
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
