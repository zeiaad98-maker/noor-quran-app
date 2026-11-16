import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quran/quran.dart' as quran;

import '../data/audio_player_controller.dart';
import '../data/quran_audio.dart';

/// Audio player bottom sheet, modelled on the SurahApp player layout
/// the user approved, in Noor colours (cream 0xFFFAF6EE, gold
/// 0xFF8A723D, green 0xFF0D6E52).
///
/// Top row (RTL): close | next | play/pause | previous | repeat-item |
/// more. Then the scope tabs (word / ayah / page / surah), the scope
/// body (page range pickers for the page scope), and at the bottom the
/// repeat-scope pill + the reciter dropdown.
class AudioPlayerSheet extends StatelessWidget {
  final AudioPlayerController controller;
  final int currentPage;

  const AudioPlayerSheet({
    super.key,
    required this.controller,
    required this.currentPage,
  });

  static const _green = Color(0xFF0D6E52);
  static const _gold = Color(0xFF8A723D);
  static const _cream = Color(0xFFFAF6EE);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetColor = isDark ? const Color(0xFF1E1F1E) : _cream;
    final textColor = isDark ? Colors.white : const Color(0xFF2D2A26);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final ayah = controller.currentAyah;
        final surah = ayah?.$1;
        final verse = ayah?.$2;
        return Container(
          decoration: BoxDecoration(
            color: sheetColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _topRow(context),
                const SizedBox(height: 8),
                if (ayah != null)
                  Text(
                    _currentLabel(controller, surah!, verse!),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.amiri(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _green,
                    ),
                  ),
                if (controller.scope == PlayerScope.word &&
                    controller.wordUsesWbw)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'تسجيل الكلمة بصوت موحّد — هذا القارئ ليس له مقاطع كلمة-بكلمة خاصة به',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.amiri(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 12),
                _scopeTabs(textColor),
                const SizedBox(height: 14),
                _scopeBody(context, textColor),
                const SizedBox(height: 16),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: _repeatScopePill(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _reciterDropdown(textColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _currentLabel(
      AudioPlayerController c, int surah, int verse) {
    final base =
        'سورة ${quran.getSurahNameArabic(surah)} • الآية $verse';
    if (c.scope == PlayerScope.word && c.wordIndex != null) {
      final words = quran
          .getVerse(surah, verse)
          .split(' ')
          .where((w) => w.isNotEmpty)
          .toList();
      final word = c.wordIndex! - 1 < words.length
          ? words[c.wordIndex! - 1]
          : '';
      return '$base • الكلمة: $word';
    }
    if (c.scope == PlayerScope.surah) {
      return '$base • من ${quran.getVerseCount(surah)} آية';
    }
    return base;
  }

  Widget _topRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _circleButton(
          icon: Icons.close,
          background: _green,
          foreground: Colors.white,
          tooltip: 'إغلاق وإيقاف الصوت',
          onPressed: () async {
            await controller.stop();
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
        _circleButton(
          icon: Icons.skip_next,
          tooltip: 'التالي',
          onPressed: controller.next,
        ),
        _circleButton(
          icon: controller.isPlaying ? Icons.pause : Icons.play_arrow,
          background: _green,
          foreground: Colors.white,
          size: 56,
          iconSize: 32,
          tooltip: controller.isPlaying ? 'إيقاف مؤقت' : 'تشغيل',
          onPressed: controller.isLoading
              ? null
              : controller.togglePlayPause,
          child: controller.isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : null,
        ),
        _circleButton(
          icon: Icons.skip_previous,
          tooltip: 'السابق',
          onPressed: controller.previous,
        ),
        _circleButton(
          icon: Icons.repeat_one,
          tooltip: 'تكرار العنصر الحالي',
          foreground: controller.repeatItem ? _green : Colors.grey,
          onPressed: controller.toggleRepeatItem,
        ),
        _moreButton(context),
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback? onPressed,
    Color? background,
    Color? foreground,
    double size = 44,
    double iconSize = 24,
    String? tooltip,
    Widget? child,
  }) {
    final button = SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background ?? Colors.transparent,
          foregroundColor: foreground ?? _gold,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
        child: child ?? Icon(icon, size: iconSize),
      ),
    );
    return tooltip == null
        ? button
        : Tooltip(message: tooltip, child: button);
  }

  Widget _moreButton(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: _gold),
      tooltip: 'خيارات التكرار والسرعة',
      onSelected: (value) {
        if (value.startsWith('count:')) {
          controller.setRepeatCount(int.parse(value.substring(6)));
        } else if (value.startsWith('speed:')) {
          controller.setSpeed(double.parse(value.substring(6)));
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'header-count',
          enabled: false,
          child: Text('عدد التكرار',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final (count, label) in [
          (1, 'مرة واحدة'),
          (3, '3 مرات'),
          (5, '5 مرات'),
          (10, '10 مرات'),
          (0, 'مستمر'),
        ])
          PopupMenuItem<String>(
            value: 'count:$count',
            child: Row(
              children: [
                if (controller.repeatCount == count)
                  const Icon(Icons.check, size: 18, color: _green),
                if (controller.repeatCount == count)
                  const SizedBox(width: 6),
                Text(label),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'header-speed',
          enabled: false,
          child: Text('سرعة التشغيل',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final (speed, label) in [
          (0.75, 'بطيئة 0.75×'),
          (1.0, 'عادية 1×'),
          (1.25, 'سريعة 1.25×'),
          (1.5, 'سريعة 1.5×'),
        ])
          PopupMenuItem<String>(
            value: 'speed:$speed',
            child: Row(
              children: [
                if (controller.speed == speed)
                  const Icon(Icons.check, size: 18, color: _green),
                if (controller.speed == speed) const SizedBox(width: 6),
                Text(label),
              ],
            ),
          ),
      ],
    );
  }

  Widget _scopeTabs(Color textColor) {
    const tabs = [
      (PlayerScope.word, 'الكلمة'),
      (PlayerScope.ayah, 'الآية'),
      (PlayerScope.page, 'الصفحة'),
      (PlayerScope.surah, 'السورة'),
    ];
    return Row(
      children: [
        for (final (scope, label) in tabs)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _switchScope(scope),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: controller.scope == scope
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: controller.scope == scope
                          ? _gold
                          : Colors.grey.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.amiri(
                      fontSize: 16,
                      fontWeight: controller.scope == scope
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: controller.scope == scope ? _green : textColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _switchScope(PlayerScope scope) {
    final ayah = controller.currentAyah;
    switch (scope) {
      case PlayerScope.word:
        // A word scope needs a word: it is set when the player is
        // opened from a tapped word. Without one, stay put and let
        // the body explain how to pick a word.
        if (controller.wordIndex != null && ayah != null) {
          controller.playWord(ayah.$1, ayah.$2, controller.wordIndex!);
        }
      case PlayerScope.ayah:
        if (ayah != null) controller.playAyah(ayah.$1, ayah.$2);
      case PlayerScope.page:
        controller.playPages(currentPage, currentPage);
      case PlayerScope.surah:
        if (ayah != null) controller.playSurah(ayah.$1);
    }
  }

  Widget _scopeBody(BuildContext context, Color textColor) {
    switch (controller.scope) {
      case PlayerScope.word:
        return _wordBody(textColor);
      case PlayerScope.ayah:
        return _ayahBody(textColor);
      case PlayerScope.page:
        return _pageBody(textColor);
      case PlayerScope.surah:
        return _surahBody(textColor);
    }
  }

  Widget _wordBody(Color textColor) {
    final ayah = controller.currentAyah;
    if (ayah == null || controller.wordIndex == null) {
      return Text(
        'لتشغيل كلمة مفردة: اضغط على أي آية في المصحف، ثم اضغط على الكلمة في شيت الآية.',
        textAlign: TextAlign.center,
        style: GoogleFonts.amiri(fontSize: 15, color: Colors.grey),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        quran.getVerse(ayah.$1, ayah.$2),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Hafs',
          fontSize: 21,
          height: 1.9,
          color: textColor,
        ),
      ),
    );
  }

  Widget _ayahBody(Color textColor) {
    final ayah = controller.currentAyah;
    if (ayah == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        quran.getVerse(ayah.$1, ayah.$2),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Hafs',
          fontSize: 21,
          height: 1.9,
          color: textColor,
        ),
      ),
    );
  }

  Widget _pageBody(Color textColor) {
    return Column(
      children: [
        Text(
          'الاستماع لصفحات محددة',
          style: GoogleFonts.amiri(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('من صفحة ', style: GoogleFonts.amiri(fontSize: 15)),
            _pageDropdown(
              value: controller.fromPage,
              onChanged: (v) {
                if (v == null) return;
                final to = v > controller.toPage ? v : controller.toPage;
                controller.playPages(v, to);
              },
            ),
            const SizedBox(width: 16),
            Text('إلى صفحة ', style: GoogleFonts.amiri(fontSize: 15)),
            _pageDropdown(
              value: controller.toPage,
              onChanged: (v) {
                if (v == null) return;
                final from =
                    v < controller.fromPage ? v : controller.fromPage;
                controller.playPages(from, v);
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _circleButton(
          icon: controller.isPlaying ? Icons.pause : Icons.play_arrow,
          background: _green,
          foreground: Colors.white,
          size: 56,
          iconSize: 32,
          tooltip: controller.isPlaying ? 'إيقاف مؤقت' : 'تشغيل الصفحات',
          onPressed: controller.togglePlayPause,
        ),
      ],
    );
  }

  Widget _pageDropdown({
    required int value,
    required void Function(int?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _gold.withValues(alpha: 0.5)),
      ),
      child: DropdownButton<int>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (var p = 1; p <= 604; p++)
            DropdownMenuItem(value: p, child: Text('$p')),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _surahBody(Color textColor) {
    final ayah = controller.currentAyah;
    if (ayah == null) return const SizedBox.shrink();
    final total = quran.getVerseCount(ayah.$1);
    return Text(
      'سورة ${quran.getSurahNameArabic(ayah.$1)} كاملة — $total آية، '
      'بالترتيب من الآية الأولى. السابق/التالي يتنقل بين الآيات.',
      textAlign: TextAlign.center,
      style: GoogleFonts.amiri(fontSize: 15, color: textColor),
    );
  }

  Widget _repeatScopePill() {
    final active = controller.repeatScope;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: controller.toggleRepeatScope,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? _green : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? _green : Colors.grey.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.repeat,
                size: 18, color: active ? Colors.white : _gold),
            const SizedBox(width: 6),
            Text(
              'تكرار النطاق',
              style: GoogleFonts.amiri(
                fontSize: 15,
                color: active ? Colors.white : _gold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reciterDropdown(Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _gold.withValues(alpha: 0.5)),
      ),
      child: DropdownButton<int>(
        value: controller.reciterIndex,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        icon: const Icon(Icons.arrow_drop_down, color: _gold),
        items: [
          for (var i = 0; i < reciters.length; i++)
            DropdownMenuItem(
              value: i,
              child: Text(
                reciters[i].name,
                style: GoogleFonts.amiri(fontSize: 15, color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (v) {
          if (v != null) controller.setReciter(v);
        },
      ),
    );
  }
}
