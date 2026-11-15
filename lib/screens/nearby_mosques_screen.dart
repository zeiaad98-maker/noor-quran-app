import 'dart:convert';
import 'package:material_ui/material_ui.dart';
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
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _mosques = [];

  @override
  void initState() {
    super.initState();
    _fetchNearbyMosques();
  }

  Future<void> _fetchNearbyMosques() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // البحث في دائرة نصف قطرها 3000 متر (3 كم) حول موقع المستخدم عبر OpenStreetMap
      final query = '''
[out:json][timeout:15];
(
  node["amenity"="place_of_worship"]["religion"="muslim"](around:3000,${widget.lat},${widget.lng});
  way["amenity"="place_of_worship"]["religion"="muslim"](around:3000,${widget.lat},${widget.lng});
);
out center;
''';
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: {'data': query},
      );

      if (response.statusCode != 200) {
        throw Exception('تعذر الاتصال بخادم الخرائط');
      }

      final data = json.decode(utf8.decode(response.bodyBytes));
      final elements = (data['elements'] as List?) ?? [];

      final List<Map<String, dynamic>> loaded = [];
      for (final el in elements) {
        final double? mLat = el['lat'] ?? el['center']?['lat'];
        final double? mLng = el['lon'] ?? el['center']?['lon'];
        if (mLat == null || mLng == null) continue;

        final tags = (el['tags'] as Map?) ?? {};
        final String name = tags['name:ar'] ?? tags['name'] ?? 'مسجد';
        final double distanceMeters = Geolocator.distanceBetween(
          widget.lat,
          widget.lng,
          mLat,
          mLng,
        );

        loaded.add({
          'name': name,
          'lat': mLat,
          'lng': mLng,
          'distance': distanceMeters,
        });
      }

      // ترتيب المساجد من الأقرب إلى الأبعد
      loaded.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

      setState(() {
        _mosques = loaded;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'تعذر جلب المساجد القريبة، تأكد من اتصال الإنترنت ثم أعد المحاولة.';
        _isLoading = false;
      });
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} متر';
    }
    return '${(meters / 1000).toStringAsFixed(1)} كم';
  }

  Future<void> _openInMaps(double lat, double lng, String name) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      final fallback = Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(name)})');
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    const emerald = Color(0xFF0C6E52);
    const gold = Color(0xFFB8934A);

    return Scaffold(
      appBar: AppBar(
        title: Text('المساجد القريبة (${widget.cityName})', style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchNearbyMosques,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: emerald),
                  SizedBox(height: 12),
                  Text('جاري البحث عن المساجد القريبة من موقعك...'),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.location_off_rounded, size: 54, color: gold),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _fetchNearbyMosques,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                )
              : _mosques.isEmpty
                  ? const Center(child: Text('لم يتم العثور على مساجد مسجلة في نطاق 3 كم'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: _mosques.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final m = _mosques[index];
                        final isNearest = index == 0;
                        return Card(
                          elevation: isNearest ? 3 : 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: isNearest ? emerald : gold.withValues(alpha: 0.25),
                              width: isNearest ? 1.6 : 1,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor: isNearest ? emerald : gold.withValues(alpha: 0.18),
                              child: Icon(
                                Icons.mosque_rounded,
                                color: isNearest ? Colors.white : gold,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    m['name'],
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                                      'الأقرب إليك',
                                      style: TextStyle(fontSize: 11, color: emerald, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                children: [
                                  const Icon(Icons.directions_walk_rounded, size: 16, color: gold),
                                  const SizedBox(width: 4),
                                  Text(
                                    'يبعد عنك: ${_formatDistance(m['distance'])}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            trailing: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: emerald,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              onPressed: () => _openInMaps(m['lat'], m['lng'], m['name']),
                              icon: const Icon(Icons.navigation_rounded, size: 16),
                              label: const Text('اتجاه'),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
