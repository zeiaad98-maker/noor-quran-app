import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:google_fonts/google_fonts.dart';

class TasbeehScreen extends StatefulWidget {
  const TasbeehScreen({super.key});

  @override
  State<TasbeehScreen> createState() => _TasbeehScreenState();
}

class _TasbeehScreenState extends State<TasbeehScreen> {
  int _counter = 0;
  int _totalCount = 0;
  int _target = 100;
  bool _vibrate = true;

  final List<String> _adhkar = [
    'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ',
    'سُبْحَانَ اللَّهِ العَظِيم',
    'أَسْتَغْفِرُ اللَّهَ وَأَتُوبُ إِلَيْه',
    'اللَّهُمَّ صَلِّ وَسَلِّمْ عَلَى نَبِيِّنَا مُحَمَّد',
    'لَا إِلَهَ إِلَّا اللَّهُ',
    'الحَمْدُ لِلَّه',
    'اللَّهُ أَكْبَر',
    'لَا حَوْلَ وَلَا قُوَّةَ إِلَّا بِاللَّه',
  ];

  late String _currentDhikr;
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    _currentDhikr = _adhkar[0];
    _loadData();
  }

  Future<void> _loadData() async {
    _prefs = await SharedPreferences.getInstance();
    setState(() {
      _totalCount = _prefs.getInt('tasbeeh_total') ?? 0;
      _vibrate = _prefs.getBool('tasbeeh_vibrate') ?? true;
      _target = _prefs.getInt('tasbeeh_target') ?? 100;
    });
  }

  void _increment() async {
    setState(() {
      _counter++;
      _totalCount++;
    });
    _prefs.setInt('tasbeeh_total', _totalCount);

    if (_vibrate) {
      if (_counter == _target) {
        // اهتزاز طويل عند الوصول للهدف
        if (await Vibration.hasVibrator()) {
          Vibration.vibrate(duration: 500);
        }
        setState(() => _counter = 0); // إعادة التصفير تلقائياً بعد بلوغ الهدف
      } else {
        // اهتزاز خفيف لكل ضغطة
        if (await Vibration.hasVibrator()) {
          Vibration.vibrate(duration: 50, amplitude: 50);
        }
      }
    } else if (_counter == _target) {
       setState(() => _counter = 0);
    }
  }

  void _reset() {
    setState(() => _counter = 0);
  }

  void _addCustomDhikr() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة ذكر جديد'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'اكتب الذكر هنا...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _adhkar.insert(0, controller.text.trim());
                  _currentDhikr = controller.text.trim();
                  _counter = 0;
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const darkBg = Color(0xFF131715);
    const emerald = Color(0xFF0C6E52);
    const gold = Color(0xFFC7A35F);

    return Scaffold(
      backgroundColor: isDark ? darkBg : const Color(0xFFF6F3EA),
      // v11 Bug G: the old fixed-height Column with two Spacers
      // overflowed the space above the bottom nav (AppBar + Adhkar
      // TabBar + NavigationBar eat ~260dp of a 919dp screen), so
      // the target pills — and the vibration row — were clipped
      // behind the nav bar. The body is now scrollable AND the
      // circle shrinks to fit the available height, so on a normal
      // phone everything fits with no scrolling at all; on a
      // shorter screen it scrolls instead of clipping.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Fixed parts (strip + gaps + dhikr card + totals card +
            // switch row + paddings) need ~404dp; the circle takes
            // the rest, 180–260dp, and the counter font scales with
            // it. At the 656dp available in the 411×919 tab chrome
            // the circle is 252dp and the whole screen fits.
            final circleD =
                (constraints.maxHeight - 404).clamp(180.0, 260.0);
            final counterFont = (circleD * 0.246).clamp(44.0, 64.0);
            return SingleChildScrollView(
              child: Column(
                children: [
                  _adhkarStrip(isDark, emerald, gold),
                  const SizedBox(height: 16),
                  _dhikrCard(isDark, gold),
                  const SizedBox(height: 16),
                  _tapCircle(emerald, gold, circleD, counterFont),
                  const SizedBox(height: 16),
                  _totalsCard(isDark, emerald, gold),
                  const SizedBox(height: 12),
                  _vibrateRow(emerald),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // 1. شريط الأذكار العلوي
  Widget _adhkarStrip(bool isDark, Color emerald, Color gold) {
    return Container(
      height: 54,
      margin: const EdgeInsets.only(top: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _adhkar.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == _adhkar.length) {
            return InkWell(
              onTap: _addCustomDhikr,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2421) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: gold.withValues(alpha: 0.5)),
                ),
                alignment: Alignment.center,
                child: Row(
                  children: [
                    Icon(Icons.add, color: gold, size: 18),
                    SizedBox(width: 4),
                    Text('إضافة ذكر', style: TextStyle(color: gold, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            );
          }
          final dhikr = _adhkar[index];
          final isSelected = dhikr == _currentDhikr;
          return InkWell(
            onTap: () => setState(() {
              _currentDhikr = dhikr;
              _counter = 0;
            }),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected ? emerald.withValues(alpha: 0.15) : (isDark ? const Color(0xFF1E2421) : Colors.white),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? emerald : (isDark ? Colors.white12 : Colors.black12)),
              ),
              alignment: Alignment.center,
              child: Text(
                dhikr,
                style: TextStyle(
                  color: isSelected ? emerald : (isDark ? Colors.white : Colors.black),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // 2. بطاقة الذكر الحالي المحددة
  Widget _dhikrCard(bool isDark, Color gold) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1F1D) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: gold.withValues(alpha: 0.3)),
        ),
        child: Text(
          _currentDhikr,
          textAlign: TextAlign.center,
          style: GoogleFonts.amiriQuran(
            fontSize: 26,
            color: gold,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  // 3. دائرة السبحة الكبرى — responsive: [circleD] is computed from
  // the available height (see build), and the counter font scales
  // with it so the digits never crowd the circle.
  Widget _tapCircle(
    Color emerald,
    Color gold,
    double circleD,
    double counterFont,
  ) {
    return GestureDetector(
      onTap: _increment,
      child: Container(
        width: circleD,
        height: circleD,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: emerald,
          border: Border.all(color: gold.withValues(alpha: 0.8), width: 8),
          boxShadow: [
            BoxShadow(
              color: emerald.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$_counter',
                style: TextStyle(
                  fontSize: counterFont,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'الهدف: $_target',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 4. بطاقة الأهداف والمجموع الكلي
  Widget _totalsCard(bool isDark, Color emerald, Color gold) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1F1D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gold.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('المجموع الكلي: $_totalCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.redAccent, size: 20),
                tooltip: 'تصفير العداد الحالي',
                onPressed: _reset,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [33, 99, 100, 500, 1000].map((t) {
              final isSel = _target == t;
              return InkWell(
                onTap: () {
                  setState(() => _target = t);
                  _prefs.setInt('tasbeeh_target', t);
                },
                child: Container(
                  // Was 14px horizontal: the 5 pills overflowed
                  // their 337dp row by 2.5px at 411dp.
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSel ? gold : (isDark ? const Color(0xFF262C29) : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$t',
                    style: TextStyle(
                      color: isSel ? (isDark ? Colors.black : Colors.white) : (isDark ? Colors.white : Colors.black),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // 5. مفتاح الاهتزاز
  Widget _vibrateRow(Color emerald) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('اهتزاز عند العد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Switch(
            value: _vibrate,
            activeThumbColor: emerald,
            onChanged: (val) {
              setState(() => _vibrate = val);
              _prefs.setBool('tasbeeh_vibrate', val);
            },
          ),
        ],
      ),
    );
  }
}
