import 'package:material_ui/material_ui.dart';
import 'package:quran/quran.dart' as quran;

/// Ornate calligraphy image of a surah name (`assets/surah_names/n.png`).
/// The images are black on transparency: in dark mode they are tinted
/// light gold so they stay visible on the dark background; in light mode
/// they are shown as-is (black). Falls back to plain text if the image
/// cannot be loaded.
///
/// The asset canvas is 1080×174 but the ink occupies only the central
/// part (measured across all 114 files: x 401–679, y 37–148) — at a
/// plain `height: 30` the visible calligraphy was only ~13dp tall,
/// which is why the user read the list names as "very tiny". With
/// [cropPadding] the transparent padding is cropped away (ClipRect +
/// OverflowBox) so the calligraphy itself fills the widget: the ink
/// is up to ~89% of the widget height instead of ~43% of a
/// mostly-empty canvas. The crop window (central 30% × 72%) covers
/// every surah's ink with margin — verified against all 114 assets.
class SurahNameImage extends StatelessWidget {
  final int surahNumber;
  final double height;
  final bool isDark;
  final bool cropPadding;

  const SurahNameImage({
    super.key,
    required this.surahNumber,
    required this.height,
    required this.isDark,
    this.cropPadding = false,
  });

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
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
    if (!cropPadding) return image;
    // Canvas aspect 1080/174 ≈ 6.21; the OverflowBox lets the image
    // keep its full height (and intrinsic width) even though the
    // window is narrower, and the ClipRect cuts the empty padding.
    final width = height * 1080 / 174;
    return ClipRect(
      child: SizedBox(
        width: width * 0.30,
        height: height * 0.72,
        child: OverflowBox(
          maxWidth: width,
          maxHeight: height,
          alignment: Alignment.center,
          child: image,
        ),
      ),
    );
  }
}
