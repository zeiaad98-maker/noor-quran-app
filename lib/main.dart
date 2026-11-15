import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/surah_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('is_dark_mode') ?? false; // الفاتح هو الافتراضي الآن
  runApp(NoorQuranApp(initialDarkMode: isDark));
}

class NoorQuranApp extends StatefulWidget {
  final bool initialDarkMode;
  const NoorQuranApp({super.key, this.initialDarkMode = false});

  static _NoorQuranAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_NoorQuranAppState>();

  @override
  State<NoorQuranApp> createState() => _NoorQuranAppState();
}

class _NoorQuranAppState extends State<NoorQuranApp> {
  late bool _isDarkMode;

  @override
  void initState() {
    super.initState();
    _isDarkMode = widget.initialDarkMode;
  }

  Future<void> toggleTheme() async {
    setState(() => _isDarkMode = !_isDarkMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', _isDarkMode);
  }

  bool get isDarkMode => _isDarkMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'نور القرآن',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'SA'),
      supportedLocales: const [Locale('ar', 'SA')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFBF8F1),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D6E52),
          brightness: Brightness.light,
          surface: const Color(0xFFFBF8F1),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D6E52),
          foregroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121614),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B8A68),
          brightness: Brightness.dark,
          surface: const Color(0xFF121614),
        ),
      ),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    SurahListScreen(),
    _PlaceholderTab(title: 'مواقيت الصلاة', icon: Icons.access_time_filled_rounded, subtitle: 'جاهز لربط الحساب الفلكي والأذان'),
    _PlaceholderTab(title: 'اتجاه القبلة', icon: Icons.explore_rounded, subtitle: 'جاهز لربط مستشعر البوصلة'),
    _PlaceholderTab(title: 'الأذكار والتسبيح', icon: Icons.favorite_rounded, subtitle: 'جاهز لربط حصن المسلم'),
  ];

  @override
  Widget build(BuildContext context) {
    final appState = NoorQuranApp.of(context);
    final isDark = appState?.isDarkMode ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('نور القرآن', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            tooltip: isDark ? 'الوضع الفاتح' : 'الوضع الداكن',
            onPressed: () => appState?.toggleTheme(),
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'المصحف'),
          NavigationDestination(icon: Icon(Icons.mosque_outlined), selectedIcon: Icon(Icons.mosque), label: 'الصلاة'),
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'القبلة'),
          NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), selectedIcon: Icon(Icons.wb_sunny), label: 'الأذكار'),
        ],
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  final String title;
  final IconData icon;
  final String subtitle;

  const _PlaceholderTab({required this.title, required this.icon, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
