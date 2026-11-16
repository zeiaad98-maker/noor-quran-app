import 'package:material_ui/material_ui.dart';
import 'package:quran/quran.dart' as quran;

/// Ornate calligraphy image of a surah name (`assets/surah_names/n.png`).
/// The images are black on transparency: in dark mode they are tinted
/// light gold so they stay visible on the dark background; in light mode
/// they are shown as-is (black). Falls back to plain text if the image
/// cannot be loaded.
class SurahNameImage extends StatelessWidget {
  final int surahNumber;
  final double height;
  final bool isDark;

  const SurahNameImage({
    super.key,
    required this.surahNumber,
    required this.height,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/surah_names/$surahNumber.png',
      height: height,
      fit: BoxFit.contain,
      color: isDark ? const Color(0xFFD2BA80) : null,
      colorBlendMode: isDark ? BlendMode.srcIn : BlendMode.srcOver,
      errorBuilder: (context, error, stackTrace) => Text(
        quran.getSurahNameArabic(surahNumber),
        style: TextStyle(
          fontSize: height * 0.7,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : const Color(0xFF2D2A26),
        ),
      ),
    );
  }
}
