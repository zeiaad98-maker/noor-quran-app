import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/surah_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('is_dark_mode') ?? false;
  runApp(NoorQuranApp(initialDarkMode: isDark));
}

class NoorQuranApp extends StatefulWidget {
  final bool initialDarkMode;
  const NoorQuranApp({super.key, this.initialDarkMode = false});

  // ignore: library_private_types_in_public_api
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
        scaffoldBackgroundColor: const Color(0xFFF6F3EA),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0C6E52),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0C6E52),
          foregroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121614),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B8A68),
          brightness: Brightness.dark,
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

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomeScreen(onOpenMushafTab: () => setState(() => _selectedIndex = 1)),
      const _SubScreenWrapper(title: 'المصحف الشريف', child: SurahListScreen()),
      const _SubScreenWrapper(title: 'الأذكار والتسبيح', child: _ComingSoon(title: 'حصن المسلم والسبحة')),
      const _SubScreenWrapper(title: 'البحث الشامل', child: _ComingSoon(title: 'البحث في آيات القرآن الكريم')),
    ];

    return Scaffold(
      body: pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book_rounded), label: 'المصحف'),
          NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'الأذكار'),
          NavigationDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search_rounded), label: 'بحث'),
        ],
      ),
    );
  }
}

class _SubScreenWrapper extends StatelessWidget {
  final String title;
  final Widget child;
  const _SubScreenWrapper({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final appState = NoorQuranApp.of(context);
    final isDark = appState?.isDarkMode ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            onPressed: () => appState?.toggleTheme(),
          ),
        ],
      ),
      body: child,
    );
  }
}

class _ComingSoon extends StatelessWidget {
  final String title;
  const _ComingSoon({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}
