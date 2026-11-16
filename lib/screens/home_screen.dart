import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:adhan/adhan.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../main.dart';
import '../data/khatma_plan.dart';
import 'khatma_screen.dart';
import 'surah_reader_screen.dart';
import 'nearby_mosques_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onOpenMushafTab;
  const HomeScreen({super.key, required this.onOpenMushafTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  final GlobalKey _calendarCardKey = GlobalKey();
  final GlobalKey _prayerCardKey = GlobalKey();
  bool _isCapturingImage = false;

  double _lat = 33.5138;
  double _lng = 36.2765;
  String _city = 'دمشق';
  String _country = 'سوريا';
  bool _isLocating = false;

  // إعدادات دقة المواقيت ومعايرة الدقائق لكل صلاة
  String _calcMethodKey = 'auto';
  int _fajrOffset = 0;
  int _sunriseOffset = 0;
  int _dhuhrOffset = 0;
  int _asrOffset = 0;
  int _maghribOffset = 0;
  int _ishaOffset = 0;

  late PrayerTimes _prayerTimes;
  int? _lastSurah;
  int? _lastPage;
  int? _khatmaDone;
  int? _khatmaTotal;

  @override
  void initState() {
    super.initState();
    _recalculatePrayers();
    _loadSavedSettings();
    _detectLocationAutomatically();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
          if (_now.hour == 0 && _now.minute == 0 && _now.second == 1) {
            _recalculatePrayers();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  CalculationParameters _resolveCalculationParams() {
    CalculationParameters params;
    final key = _calcMethodKey == 'auto' ? _detectMethodByCountry(_country) : _calcMethodKey;

    switch (key) {
      case 'syria_levant':
        // التقويم المعتمد في سوريا وبلاد الشام (فجر 18 درجة، عشاء 17.5 درجة)
        params = CalculationParameters(fajrAngle: 18.0, ishaAngle: 17.5);
        break;
      case 'umm_al_qura':
        params = CalculationMethod.umm_al_qura.getParameters();
        break;
      case 'egyptian':
        params = CalculationMethod.egyptian.getParameters();
        break;
      case 'turkey':
        params = CalculationMethod.turkey.getParameters();
        break;
      case 'karachi':
        params = CalculationMethod.karachi.getParameters();
        break;
      default:
        params = CalculationMethod.muslim_world_league.getParameters();
    }

    params.madhab = Madhab.shafi;
    params.adjustments.fajr = _fajrOffset;
    params.adjustments.sunrise = _sunriseOffset;
    params.adjustments.dhuhr = _dhuhrOffset;
    params.adjustments.asr = _asrOffset;
    params.adjustments.maghrib = _maghribOffset;
    params.adjustments.isha = _ishaOffset;
    return params;
  }

  String _detectMethodByCountry(String country) {
    final c = country.toLowerCase();
    if (c.contains('سوريا') || c.contains('syria') || c.contains('لبنان') || c.contains('الأردن') || c.contains('فلسطين')) {
      return 'syria_levant';
    }
    if (c.contains('السعودية') || c.contains('saudi') || c.contains('الإمارات') || c.contains('قطر') || c.contains('الكويت')) {
      return 'umm_al_qura';
    }
    if (c.contains('مصر') || c.contains('egypt')) {
      return 'egyptian';
    }
    if (c.contains('تركيا') || c.contains('turkey')) {
      return 'turkey';
    }
    return 'mwl';
  }

  void _recalculatePrayers() {
    final coordinates = Coordinates(_lat, _lng);
    final params = _resolveCalculationParams();
    _prayerTimes = PrayerTimes.today(coordinates, params);
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lat = prefs.getDouble('saved_lat') ?? _lat;
      _lng = prefs.getDouble('saved_lng') ?? _lng;
      _city = prefs.getString('saved_city') ?? _city;
      _country = prefs.getString('saved_country') ?? _country;
      _calcMethodKey = prefs.getString('calc_method') ?? 'auto';
      _fajrOffset = prefs.getInt('offset_fajr') ?? 0;
      _sunriseOffset = prefs.getInt('offset_sunrise') ?? 0;
      _dhuhrOffset = prefs.getInt('offset_dhuhr') ?? 0;
      _asrOffset = prefs.getInt('offset_asr') ?? 0;
      _maghribOffset = prefs.getInt('offset_maghrib') ?? 0;
      _ishaOffset = prefs.getInt('offset_isha') ?? 0;
      _lastSurah = prefs.getInt('last_surah');
      _lastPage = prefs.getInt('last_page');
      final khatmaPlan = KhatmaPlan.decode(prefs.getString('khatma_plan'));
      _khatmaDone = khatmaPlan?.completedCount;
      _khatmaTotal = khatmaPlan?.totalSessions;
      _recalculatePrayers();
    });
  }

  Future<void> _savePrayerCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('calc_method', _calcMethodKey);
    await prefs.setInt('offset_fajr', _fajrOffset);
    await prefs.setInt('offset_sunrise', _sunriseOffset);
    await prefs.setInt('offset_dhuhr', _dhuhrOffset);
    await prefs.setInt('offset_asr', _asrOffset);
    await prefs.setInt('offset_maghrib', _maghribOffset);
    await prefs.setInt('offset_isha', _ishaOffset);
    setState(() => _recalculatePrayers());
  }

  void _showPrayerCalibrationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget offsetRow(String label, int val, void Function(int) onChange) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      IconButton.outlined(
                        icon: const Icon(Icons.remove, size: 18),
                        onPressed: () {
                          onChange(val - 1);
                          setModalState(() {});
                          _savePrayerCalibration();
                        },
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          val == 0 ? '0 د' : (val > 0 ? '+$val د' : '$val د'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton.outlined(
                        icon: const Icon(Icons.add, size: 18),
                        onPressed: () {
                          onChange(val + 1);
                          setModalState(() {});
                          _savePrayerCalibration();
                        },
                      ),
                    ],
                  ),
                ],
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'ضبط دقة أوقات الصلاة',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _calcMethodKey,
                      decoration: const InputDecoration(
                        labelText: 'طريقة الحساب الفلكي',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'auto', child: Text('تلقائي حسب دولتك (موصى به)')),
                        DropdownMenuItem(value: 'syria_levant', child: Text('تقويم سوريا وبلاد الشام (18° / 17.5°)')),
                        DropdownMenuItem(value: 'umm_al_qura', child: Text('تقويم أم القرى (مكة المكرمة)')),
                        DropdownMenuItem(value: 'egyptian', child: Text('الهيئة المصرية العامة للمساحة')),
                        DropdownMenuItem(value: 'turkey', child: Text('رئاسة الشؤون الدينية التركية')),
                        DropdownMenuItem(value: 'mwl', child: Text('رابطة العالم الإسلامي')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          _calcMethodKey = v;
                          setModalState(() {});
                          _savePrayerCalibration();
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text('التعديل اليدوي بالدقائق لمطابقة المسجد المحلي:', style: TextStyle(fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 6),
                    offsetRow('الفجر', _fajrOffset, (v) => _fajrOffset = v),
                    offsetRow('الشروق', _sunriseOffset, (v) => _sunriseOffset = v),
                    offsetRow('الظهر', _dhuhrOffset, (v) => _dhuhrOffset = v),
                    offsetRow('العصر', _asrOffset, (v) => _asrOffset = v),
                    offsetRow('المغرب', _maghribOffset, (v) => _maghribOffset = v),
                    offsetRow('العشاء', _ishaOffset, (v) => _ishaOffset = v),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _detectLocationAutomatically() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      String newCity = _city;
      String newCountry = _country;
      try {
        await setLocaleIdentifier('ar');
        final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          newCity = placemarks.first.locality ?? placemarks.first.administrativeArea ?? _city;
          newCountry = placemarks.first.country ?? _country;
        }
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('saved_lat', pos.latitude);
      await prefs.setDouble('saved_lng', pos.longitude);
      await prefs.setString('saved_city', newCity);
      await prefs.setString('saved_country', newCountry);

      if (mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          _city = newCity;
          _country = newCountry;
          _recalculatePrayers();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  String _toArabicDigits(String input) {
    const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    String res = input;
    for (int i = 0; i < 10; i++) {
      res = res.replaceAll(en[i], ar[i]);
    }
    return res;
  }

  String _formatTime12(DateTime dt) {
    int h = dt.hour % 12;
    if (h == 0) h = 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return _toArabicDigits('$h:$m');
  }

  String _formatCountdown(Duration d) {
    if (d.isNegative) return '٠٠:٠٠:٠٠';
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return _toArabicDigits('$h:$m:$s');
  }

  String _getArabicDayName(int weekday) {
    const days = {
      1: 'الإثنين',
      2: 'الثلاثاء',
      3: 'الأربعاء',
      4: 'الخميس',
      5: 'الجمعة',
      6: 'السبت',
      7: 'الأحد',
    };
    return days[weekday] ?? '';
  }

  String _getHijriMonthArabic(int month) {
    const months = [
      'محرم', 'صفر', 'ربيع الأول', 'ربيع الآخر',
      'جمادى الأولى', 'جمادى الآخرة', 'رجب', 'شعبان',
      'رمضان', 'شوال', 'ذو القعدة', 'ذو الحجة'
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  String _getGregorianMonthArabic(int month) {
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  Future<void> _captureAndShareWidget(GlobalKey key, String fileName, String caption) async {
    setState(() => _isCapturingImage = true);
    await Future.delayed(const Duration(milliseconds: 60));
    try {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/$fileName.png').create();
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([XFile(file.path)], text: caption);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isCapturingImage = false);
    }
  }

  void _showShareOptions({
    required String title,
    required VoidCallback onShareImage,
    required VoidCallback onShareText,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF0C6E52),
                  child: Icon(Icons.image_rounded, color: Colors.white),
                ),
                title: const Text('مشاركة كصورة', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('بطاقة مصممة عالية الدقة جاهزة للحالات والواتساب'),
                onTap: () {
                  Navigator.pop(ctx);
                  onShareImage();
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFB8934A),
                  child: Icon(Icons.text_snippet_rounded, color: Colors.white),
                ),
                title: const Text('مشاركة كنص', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('نص منسّق قابل للنسخ والتعديل'),
                onTap: () {
                  Navigator.pop(ctx);
                  onShareText();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _shareCalendarText(HijriCalendar hijri) {
    final dayName = _getArabicDayName(_now.weekday);
    final hDay = _toArabicDigits('${hijri.hDay}');
    final hMonth = _getHijriMonthArabic(hijri.hMonth);
    final hYear = _toArabicDigits('${hijri.hYear}');
    final gDate = '${_toArabicDigits('${_now.day}')} ${_getGregorianMonthArabic(_now.month)} ${_toArabicDigits('${_now.year}')}';

    final message = '''
📅 تقويم اليوم ($dayName)
🌙 الهجري: $hDay $hMonth $hYear هـ
📆 الميلادي: $gDate م
📍 حسب تقويم $_country

— تطبيق نور القرآن 🕌
''';
    Share.share(message.trim());
  }

  void _sharePrayerTimesText(HijriCalendar hijri) {
    final dayName = _getArabicDayName(_now.weekday);
    final hDate = '${_toArabicDigits('${hijri.hDay}')} ${_getHijriMonthArabic(hijri.hMonth)} ${_toArabicDigits('${hijri.hYear}')} هـ';

    final message = '''
🕌 مواقيت الصلاة اليوم في ($_city، $_country)
📅 $dayName - $hDate

• الفجر: ${_formatTime12(_prayerTimes.fajr)}
• الشروق: ${_formatTime12(_prayerTimes.sunrise)}
• الظهر: ${_formatTime12(_prayerTimes.dhuhr)}
• العصر: ${_formatTime12(_prayerTimes.asr)}
• المغرب: ${_formatTime12(_prayerTimes.maghrib)}
• العشاء: ${_formatTime12(_prayerTimes.isha)}

— تطبيق نور القرآن 🤲
''';
    Share.share(message.trim());
  }

  Map<String, dynamic> _getPrayerState() {
    final p = _prayerTimes;
    final list = [
      {'id': Prayer.fajr, 'name': 'الفجر', 'time': p.fajr},
      {'id': Prayer.sunrise, 'name': 'الشروق', 'time': p.sunrise},
      {'id': Prayer.dhuhr, 'name': 'الظهر', 'time': p.dhuhr},
      {'id': Prayer.asr, 'name': 'العصر', 'time': p.asr},
      {'id': Prayer.maghrib, 'name': 'المغرب', 'time': p.maghrib},
      {'id': Prayer.isha, 'name': 'العشاء', 'time': p.isha},
    ];

    for (int i = 0; i < list.length; i++) {
      final t = list[i]['time'] as DateTime;
      if (_now.isBefore(t)) {
        final prev = i == 0
            ? {'name': 'العشاء', 'time': p.isha.subtract(const Duration(days: 1))}
            : list[i - 1];
        return {
          'current': prev,
          'next': list[i],
          'all': list,
        };
      }
    }

    final tomorrowFajr = p.fajr.add(const Duration(days: 1));
    return {
      'current': list.last,
      'next': {'id': Prayer.fajr, 'name': 'الفجر', 'time': tomorrowFajr},
      'all': list,
    };
  }

  @override
  Widget build(BuildContext context) {
    final appState = NoorQuranApp.of(context);
    final isDark = appState?.isDarkMode ?? false;

    HijriCalendar.setLocal('ar');
    final hijri = HijriCalendar.fromDate(_now);

    final state = _getPrayerState();
    final currentPrayer = state['current'] as Map<String, dynamic>;
    final nextPrayer = state['next'] as Map<String, dynamic>;
    final allPrayers = state['all'] as List<Map<String, dynamic>>;

    final nextTime = nextPrayer['time'] as DateTime;
    final prevTime = currentPrayer['time'] as DateTime;
    final remaining = nextTime.difference(_now);
    final totalSpan = nextTime.difference(prevTime).inSeconds;
    final elapsed = _now.difference(prevTime).inSeconds;
    final progress = totalSpan > 0 ? (elapsed / totalSpan).clamp(0.0, 1.0) : 0.0;

    final isMorning = _now.hour >= 3 && _now.hour < 15;
    final isForbiddenTime = remaining.inMinutes <= 25 &&
        (nextPrayer['name'] == 'المغرب' || nextPrayer['name'] == 'الظهر');

    const emerald = Color(0xFF0C6E52);
    const gold = Color(0xFFB8934A);
    final cardBg = isDark ? const Color(0xFF1B211E) : Colors.white;
    final pageBg = isDark ? const Color(0xFF121614) : const Color(0xFFF6F3EA);

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _detectLocationAutomatically,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. الشريط العلوي
                Row(
                  children: [
                    Text(
                      'لا تنسَ ذكر الله',
                      style: GoogleFonts.amiri(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1E2421),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.auto_awesome, color: gold, size: 18),
                    const Spacer(),
                    // زر المساجد القريبة السريع
                    _circleIconBtn(
                      icon: Icons.mosque_rounded,
                      bg: isDark ? const Color(0xFF232A27) : const Color(0xFFEBE6D8),
                      fg: emerald,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NearbyMosquesScreen(lat: _lat, lng: _lng, cityName: _city),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _circleIconBtn(
                      icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      bg: emerald,
                      fg: Colors.white,
                      onTap: () => appState?.toggleTheme(),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 2. بطاقتا التقويم الآلي والاختصارات
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: RepaintBoundary(
                        key: _calendarCardKey,
                        child: Container(
                          height: 172,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: gold.withValues(alpha: 0.25)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _getArabicDayName(_now.weekday),
                                      style: GoogleFonts.amiri(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: gold,
                                        height: 1.1,
                                      ),
                                    ),
                                    Text(
                                      _toArabicDigits('${hijri.hDay}'),
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: emerald,
                                        height: 1.15,
                                      ),
                                    ),
                                    Text(
                                      '${_getHijriMonthArabic(hijri.hMonth)} (${_toArabicDigits('${hijri.hMonth}')})\n${_toArabicDigits('${hijri.hYear}')} هـ',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white70 : const Color(0xFF2B332F),
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_toArabicDigits('${_now.day}')} ${_getGregorianMonthArabic(_now.month)} ${_toArabicDigits('${_now.year}')}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: gold.withValues(alpha: 0.9),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'حسب تقويم $_country',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? Colors.white60 : Colors.black54,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!_isCapturingImage)
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  child: InkWell(
                                    onTap: () => _showShareOptions(
                                      title: 'مشاركة بطاقة التقويم',
                                      onShareImage: () => _captureAndShareWidget(
                                        _calendarCardKey,
                                        'noor_quran_calendar',
                                        'تقويم اليوم حسب تقويم $_country — تطبيق نور القرآن',
                                      ),
                                      onShareText: () => _shareCalendarText(hijri),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4.0),
                                      child: Icon(Icons.ios_share_rounded, size: 19, color: gold),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 172,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: gold.withValues(alpha: 0.25)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            InkWell(
                              onTap: () {},
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          isMorning ? 'طاب صباحك' : 'طاب مساؤك',
                                          style: const TextStyle(fontSize: 11, color: gold, fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          isMorning ? 'أذكار\nالصباح' : 'أذكار\nالمساء',
                                          textAlign: TextAlign.left,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            height: 1.15,
                                            color: isDark ? Colors.white : const Color(0xFF1E2421),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: emerald,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isMorning ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(height: 8, color: gold.withValues(alpha: 0.2)),
                            InkWell(
                              onTap: () {
                                if (_lastSurah != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SurahReaderScreen(
                                        surahNumber: _lastSurah!,
                                        initialPage: _lastPage,
                                      ),
                                    ),
                                  );
                                } else {
                                  widget.onOpenMushafTab();
                                }
                              },
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        const Text(
                                          'ختماتي',
                                          style: TextStyle(fontSize: 11, color: gold, fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          _lastPage != null
                                              ? 'متابعة\nصفحة ${_toArabicDigits('$_lastPage')}'
                                              : 'ابدأ ختمة\nجديدة',
                                          textAlign: TextAlign.left,
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.bold,
                                            height: 1.15,
                                            color: isDark ? Colors.white : const Color(0xFF1E2421),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: gold,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 22),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // 3. شريط أوقات الصلاة + زر الضبط الدقيق + الموقع + زر المشاركة
                Row(
                  children: [
                    Container(width: 3.5, height: 20, decoration: BoxDecoration(color: gold, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _showPrayerCalibrationSheet,
                      child: Row(
                        children: [
                          Text(
                            'أوقات الصلاة',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF1E2421),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.tune_rounded, color: gold, size: 18),
                        ],
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: _detectLocationAutomatically,
                      child: Row(
                        children: [
                          Icon(
                            _isLocating ? Icons.sync_rounded : Icons.location_on_outlined,
                            size: 16,
                            color: gold,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$_city، $_country',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _showShareOptions(
                        title: 'مشاركة أوقات الصلاة ($_city)',
                        onShareImage: () => _captureAndShareWidget(
                          _prayerCardKey,
                          'noor_quran_prayers',
                          'مواقيت الصلاة اليوم في $_city، $_country — تطبيق نور القرآن',
                        ),
                        onShareText: () => _sharePrayerTimesText(hijri),
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.ios_share_rounded, size: 16, color: gold),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 4 & 5. البطاقة الكبرى + جدول الصلوات الست
                RepaintBoundary(
                  key: _prayerCardKey,
                  child: Container(
                    color: pageBg,
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFF283949),
                                Color(0xFF1D2926),
                                Color(0xFF111916),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: [
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _toArabicDigits('١٤°'),
                                                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Icon(Icons.nightlight_round, color: Colors.white70, size: 16),
                                                ],
                                              ),
                                              Text(
                                                'تحديث آلي ${_formatTime12(_now)}',
                                                style: const TextStyle(color: Colors.white60, fontSize: 9.5),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (_isCapturingImage)
                                          Text(
                                            '$_city، $_country',
                                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'باقي على ${nextPrayer['name']}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatCountdown(remaining),
                                      style: const TextStyle(
                                        color: Color(0xFF1ED788),
                                        fontSize: 40,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2,
                                        fontFeatures: [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'الصلاة الحالية: ${currentPrayer['name']} (${_formatTime12(prevTime)})',
                                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: isForbiddenTime
                                            ? Colors.amber.withValues(alpha: 0.2)
                                            : Colors.white.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: isForbiddenTime ? Colors.amber : Colors.white30,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.info_outline_rounded,
                                            size: 15,
                                            color: isForbiddenTime ? Colors.amber : Colors.white70,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            isForbiddenTime ? 'وقت نهي عن النافلة المطلقة' : 'وقت فضيلة وأداء',
                                            style: TextStyle(
                                              color: isForbiddenTime ? Colors.amber : Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: Colors.white24,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: FractionallySizedBox(
                                            widthFactor: progress,
                                            child: Container(
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF1ED788),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Align(
                                          alignment: Alignment(1.0 - (progress * 2.0), 0),
                                          child: Container(
                                            width: 16,
                                            height: 16,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF111916),
                                              shape: BoxShape.circle,
                                              border: Border.all(color: gold, width: 3),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              currentPrayer['name'],
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                            ),
                                            Text(
                                              _formatTime12(prevTime),
                                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              nextPrayer['name'],
                                              style: const TextStyle(color: Color(0xFF1ED788), fontWeight: FontWeight.bold, fontSize: 14),
                                            ),
                                            Text(
                                              _formatTime12(nextTime),
                                              style: const TextStyle(color: Colors.white, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
                                ),
                                child: const Text(
                                  'لا يجوز تأخير الصلاة عن وقتها إلا لعذر شرعي',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: gold.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: allPrayers.map((item) {
                              final isNext = item['name'] == nextPrayer['name'];
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isNext ? emerald.withValues(alpha: 0.15) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: isNext ? Border.all(color: emerald, width: 1.2) : null,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      item['name'],
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: isNext ? FontWeight.bold : FontWeight.w600,
                                        color: isNext ? emerald : (isDark ? Colors.white70 : Colors.black87),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatTime12(item['time'] as DateTime),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isNext ? emerald : (isDark ? Colors.white : const Color(0xFF1E2421)),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // 6. بطاقة المساجد القريبة التفاعلية
                Card(
                  color: cardBg,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: gold.withValues(alpha: 0.3)),
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: emerald,
                      child: Icon(Icons.mosque_rounded, color: Colors.white),
                    ),
                    title: const Text('المساجد القريبة منك', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('عرض أقرب المساجد في $_city والاتجاه إليها'),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: gold),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NearbyMosquesScreen(lat: _lat, lng: _lng, cityName: _city),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                // 7. بطاقة خطتي للختمة
                Card(
                  color: cardBg,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: gold.withValues(alpha: 0.3)),
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: gold,
                      child: Icon(Icons.menu_book_rounded, color: Colors.white),
                    ),
                    title: const Text('خطتي للختمة', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(_khatmaTotal != null
                        ? 'أنجزت ${_toArabicDigits('$_khatmaDone')} من ${_toArabicDigits('$_khatmaTotal')} جلسات'
                        : 'ابدأ خطة ختمة: 30 أو 15 أو 7 أيام، أو خطة مخصصة'),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: gold),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const KhatmaScreen()),
                    ).then((_) => _loadSavedSettings()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleIconBtn({
    required IconData icon,
    required Color bg,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, color: fg, size: 21),
      ),
    );
  }
}
