import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qcf_quran/qcf_quran.dart';

import '../data/qcf_word_map.dart';

/// Worst-case natural height of a 15-line Mushaf page at `h = 1.0`,
/// for a screen whose calibrated font scale is [sp].
///
/// The largest per-page base font among 15-line pages is 23.7
/// (pages 51 and 501 — see qcf_quran's `page_font_size.dart`); one
/// verse line is `base × sp × verseHeight` tall, so 15 lines are
/// `15 × 23.7 × verseHeight × sp`. The extra 12dp covers the lines
/// that run taller than a plain verse line (surah headers and
/// basmalas on multi-surah pages): measured over all 604 pages, the
/// tallest real paragraph is 792dp at 411dp width and 825dp at
/// 432dp; this formula gives 793.4 / 833.4 there. Pages 1–2 are
/// shorter (8 lines) and never bind.
///
/// Verified by `test/mushaf_vertical_fit_test.dart`, which measures
/// every page's real paragraph height at the computed `h` and asserts
/// it fits the available height at 411×919, 432×965 and 390×844.
double mushafMaxNaturalHeight(double sp, {double verseHeight = 2.1}) =>
    15 * 23.7 * verseHeight * sp + 12;

/// Line-height factor that fits the tallest Mushaf page into
/// [availableHeight] without changing the font size — so the Madinah
/// horizontal line breaks are untouched, only the line spacing
/// shrinks. Never above 1.0: a page shorter than the available
/// height simply keeps the calibrated spacing.
double mushafHeightFactor(
  double availableHeight,
  double sp, {
  double verseHeight = 2.1,
}) {
  final natural = mushafMaxNaturalHeight(sp, verseHeight: verseHeight);
  return (availableHeight / natural).clamp(0.0, 1.0);
}

/// Local copy of qcf_quran 0.0.5's [QcfPage] with ONE fix.
///
/// **The bug in the package:** [QcfPage] renders each verse with
/// `getVerseQCF(surah, v, verseEndSymbol: false)`, which strips BOTH the
/// verse-end glyph AND a trailing `'\n'` when the verse ends exactly at a
/// printed Mushaf line end, then re-adds only the glyph as a child span.
/// The lost `'\n'` removes the hard line break, so the next verse flows
/// onto the same line and two printed lines merge into one: ~92 of the
/// 604 pages rendered 14 lines (some 13, a few 16) instead of 15.
///
/// **The fix** (same pattern the package itself already uses in its
/// `QcfVerse` and `QcfVerses` widgets, but forgot in `QcfPage`): when a
/// verse's full QCF data ends with `'\n'`, append a `TextSpan(text: '\n')`
/// after the verse-number glyph span. The `'\n'` is skipped after the
/// last verse of the page (no successor can flow onto its line, and a
/// trailing newline would only add a phantom empty line).
///
/// Everything else is copied verbatim from the package version so the
/// rendering (fonts, sizes, header, basmala, gestures, theme) stays
/// identical. Do NOT edit the package in pub-cache instead: pub-cache is
/// not committed and CI would not see the change.
class NoorQcfPage extends StatelessWidget {
  /// The 1-based page number (1..604).
  final int pageNumber;

  /// Theme configuration for styling the page.
  final QcfThemeData theme;

  /// Optional font size override.
  final double? fontSize;

  /// Scaling factor for screen width/pixel density (default 1.0).
  final double sp;

  /// Scaling factor for screen height (default 1.0).
  final double h;

  /// Callback when a verse is long-pressed.
  final void Function(int surahNumber, int verseNumber)? onLongPress;

  /// Callback when long-press ends.
  final void Function(int surahNumber, int verseNumber)? onLongPressUp;

  /// Callback when long-press is cancelled.
  final void Function(int surahNumber, int verseNumber)? onLongPressCancel;

  /// Callback when long-press starts (includes details).
  final void Function(
    int surahNumber,
    int verseNumber,
    LongPressStartDetails details,
  )?
  onLongPressDown;

  /// Callback when a verse is tapped.
  final void Function(int surahNumber, int verseNumber)? onTap;

  /// Callback when a single WORD is tapped (per-word popup).
  ///
  /// When set, each word of each verse gets its own recognizer
  /// reporting (surah, verse, wordIndex) — the TRUE Uthmani word
  /// index from [buildQcfWordMap], the same index the word audio
  /// and the Quran.com segments use. The verse-end number glyph
  /// keeps [onTap] (it opens the ayah sheet), so the two gestures
  /// never conflict. When [onWordTap] is null, word taps fall back
  /// to [onTap] (the old whole-verse behaviour).
  final void Function(int surahNumber, int verseNumber, int wordIndex)?
  onWordTap;

  /// Optional callback to customize verse background color dynamically.
  final Color? Function(int surahNumber, int verseNumber)?
  verseBackgroundColor;

  const NoorQcfPage({
    super.key,
    required this.pageNumber,
    this.theme = const QcfThemeData(),
    this.fontSize,
    this.sp = 1.0,
    this.h = 1.0,
    this.onLongPress,
    this.onLongPressUp,
    this.onLongPressCancel,
    this.onLongPressDown,
    this.onTap,
    this.onWordTap,
    this.verseBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    // Validate page number
    if (pageNumber < 1 || pageNumber > 604) {
      return Center(child: Text('Invalid page number: $pageNumber'));
    }

    final ranges = getPageData(pageNumber);
    final pageFont = "QCF_P${pageNumber.toString().padLeft(3, '0')}";
    // Note: User preferred multiplication logic for scaling
    final baseFontSize = getFontSize(pageNumber, context) * sp;
    final screenSize = MediaQuery.of(context).size;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    // Last verse rendered on this page: its trailing '\n' (if any) is
    // NOT re-added (see class doc) — there is no next verse to merge.
    final lastSurah = int.parse(ranges.last['surah'].toString());
    final lastVerse = int.parse(ranges.last['end'].toString());

    final verseSpans = <InlineSpan>[];
    if (pageNumber == 2 || pageNumber == 1) {
      verseSpans.add(
        WidgetSpan(child: SizedBox(height: screenSize.height * .175)),
      );
    }
    for (final r in ranges) {
      final surah = int.parse(r['surah'].toString());
      final start = int.parse(r['start'].toString());
      final end = int.parse(r['end'].toString());

      for (int v = start; v <= end; v++) {
        if (v == start && v == 1) {
          if (theme.showHeader) {
            verseSpans.add(
              WidgetSpan(child: HeaderWidget(suraNumber: surah, theme: theme)),
            );
          }
          if (theme.showBasmala && pageNumber != 1 && pageNumber != 187) {
            // Check for custom Basmala builder
            if (theme.basmalaBuilder != null) {
              verseSpans.add(
                WidgetSpan(
                  child: theme.basmalaBuilder!(surah),
                  alignment: PlaceholderAlignment.middle,
                ),
              );
              // Add a newline after custom builder to maintain layout flow if needed
              // or let the builder handle it. Usually basmala is a block.
              // We'll add a newline ensuring separation.
              verseSpans.add(const TextSpan(text: "\n"));
            } else {
              verseSpans.add(
                TextSpan(
                  text: " ﱁ  ﱂﱃﱄ\n",
                  style: TextStyle(
                    fontFamily: "QCF_P001",
                    package: 'qcf_quran',
                    fontSize:
                        getScreenType(context) == ScreenType.large
                            ? theme.basmalaFontSizeLarge * sp
                            : theme.basmalaFontSizeSmall * sp,
                    color: theme.basmalaColor,
                  ),
                ),
              );
            }
          }
        }

        // Per-word gestures (v10 — word popup).
        //
        // The verse text is one QCF glyph string: each code unit is
        // one glyph (a word, or a pause mark) or a '\n' line break.
        // [buildQcfWordMap] tells us which TRUE word each glyph
        // belongs to, so we group consecutive glyphs of the same word
        // into one TextSpan with its own recognizer. The character
        // sequence is UNCHANGED (same glyphs, same '\n's, same style)
        // — only the span boundaries move, so the line breaks and
        // the 15-line layout are identical.
        //
        // * a word span: [onWordTap] (surah, verse, wordIndex) when
        //   set; otherwise [onTap] (the old whole-verse tap); otherwise
        //   the long-press recognizer as before.
        // * the verse-end number glyph: [onTap] (opens the ayah
        //   sheet) — tapping the ۝ number is the way to reach notes,
        //   ayah audio and the rest of the ayah sheet.
        // * '\n' line breaks: plain spans, no recognizer.
        // * the hair space U+200A after the first glyph of the
        //   page's first verse is kept exactly as before.
        GestureRecognizer? wordRecognizer(int wordIndex) {
          if (onWordTap != null) {
            return TapGestureRecognizer()
              ..onTap = () => onWordTap?.call(surah, v, wordIndex);
          }
          if (onTap != null) {
            return TapGestureRecognizer()
              ..onTap = () => onTap?.call(surah, v);
          }
          if (onLongPress != null ||
              onLongPressDown != null ||
              onLongPressUp != null) {
            final r = LongPressGestureRecognizer();
            r.onLongPress = () => onLongPress?.call(surah, v);
            r.onLongPressStart =
                (d) => onLongPressDown?.call(surah, v, d);
            r.onLongPressUp = () => onLongPressUp?.call(surah, v);
            r.onLongPressEnd = (d) => onLongPressCancel?.call(surah, v);
            return r;
          }
          return null;
        }

        GestureRecognizer? numberRecognizer() {
          if (onTap != null) {
            return TapGestureRecognizer()
              ..onTap = () => onTap?.call(surah, v);
          }
          if (onLongPress != null ||
              onLongPressDown != null ||
              onLongPressUp != null) {
            final r = LongPressGestureRecognizer();
            r.onLongPress = () => onLongPress?.call(surah, v);
            r.onLongPressStart =
                (d) => onLongPressDown?.call(surah, v, d);
            r.onLongPressUp = () => onLongPressUp?.call(surah, v);
            r.onLongPressEnd = (d) => onLongPressCancel?.call(surah, v);
            return r;
          }
          return null;
        }

        final verseBgColor =
            theme.verseBackgroundColor?.call(surah, v) ??
            verseBackgroundColor?.call(surah, v);
        final verseBgStyle =
            verseBgColor != null
                ? TextStyle(backgroundColor: verseBgColor)
                : null;

        // Verse Number Logic
        InlineSpan verseNumberSpan;
        if (theme.verseNumberBuilder != null) {
          verseNumberSpan = theme.verseNumberBuilder!(
            surah,
            v,
            getVerseNumberQCF(surah, v),
          );
        } else {
          verseNumberSpan = TextSpan(
            text: getVerseNumberQCF(surah, v),
            recognizer: numberRecognizer(),
            style: TextStyle(
              fontFamily: pageFont,
              package: 'qcf_quran',
              color: theme.verseNumberColor,
              height: theme.verseNumberHeight * h,
              backgroundColor: theme.verseNumberBackgroundColor ?? verseBgColor,
            ),
          );
        }

        // FIX (see class doc): the package's verseEndSymbol:false strips a
        // trailing '\n' together with the verse-end glyph. Restore the
        // hard line break after the glyph, except after the page's last
        // verse. The full QCF data tells us whether this verse ends a
        // printed line.
        final fullVerse = getVerseQCF(surah, v, verseEndSymbol: true);
        final endsPrintedLine = fullVerse.endsWith('\n');
        final isLastVerseOfPage = surah == lastSurah && v == lastVerse;
        final verseText = getVerseQCF(surah, v, verseEndSymbol: false);
        final wordMap = buildQcfWordMap(surah, v);
        final isFirstVerseOnPage = v == ranges[0]['start'];
        // Safe glyph→word lookup: for the single best-effort verse
        // (13:10 — one glyph more than the text predicts) the extra
        // glyph maps to the last word instead of crashing.
        int glyphWord(int ordinal) =>
            ordinal < wordMap.glyphToWord.length
                ? wordMap.glyphToWord[ordinal]
                : wordMap.wordCount - 1;

        var glyphOrdinal = 0;
        var isFirstGlyph = true;
        var i = 0;
        while (i < verseText.length) {
          final c = verseText.codeUnitAt(i);
          if (c == 10) {
            // '\n' line break inside the verse: plain span.
            verseSpans.add(const TextSpan(text: '\n'));
            i++;
            continue;
          }
          // One maximal run of glyphs belonging to the same word.
          final wordIndex = glyphWord(glyphOrdinal);
          final buf = StringBuffer();
          while (i < verseText.length) {
            final c2 = verseText.codeUnitAt(i);
            if (c2 == 10) break;
            if (glyphWord(glyphOrdinal) != wordIndex) break;
            buf.writeCharCode(c2);
            if (isFirstGlyph && isFirstVerseOnPage) {
              buf.write('\u200A');
            }
            isFirstGlyph = false;
            glyphOrdinal++;
            i++;
          }
          verseSpans.add(
            TextSpan(
              text: buf.toString(),
              recognizer: wordRecognizer(wordIndex),
              style: verseBgStyle,
            ),
          );
        }
        verseSpans.add(verseNumberSpan);
        if (endsPrintedLine && !isLastVerseOfPage) {
          verseSpans.add(const TextSpan(text: '\n'));
        }
      }
    }

    // Vertical fit (v9 — page 5 clipped on the phone):
    // 1) The scrollables get EXPLICIT zero padding. A null padding
    //    makes BoxScrollView consume the MediaQuery system padding,
    //    and the reader's no-scaling MediaQuery wrapper carries the
    //    FULL padding (status bar 24dp + nav bar) because its context
    //    sits above the SafeArea — so the whole page was pushed down
    //    24dp inside the viewport and the last lines clipped.
    // 2) The SizedBox is the AVAILABLE height (the PageView viewport
    //    from LayoutBuilder), not the full screen height — a taller
    //    box left a phantom scroll area (maxScrollExtent 133dp) and
    //    the page could scroll, hiding lines below the fold.
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight =
            constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : screenSize.height;
        return Stack(
          children: [
            Scrollbar(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: SizedBox(
                  height: viewportHeight,
                  width: screenSize.width,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: Padding(
                          padding: EdgeInsets.zero,
                          child: Text.rich(
                            TextSpan(children: verseSpans),
                            locale: const Locale("ar"),
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontFamily: pageFont,
                              package: 'qcf_quran',
                              fontSize:
                                  isPortrait
                                      ? baseFontSize
                                      : (pageNumber == 1 || pageNumber == 2)
                                      ? 20 * sp
                                      : baseFontSize - (17 * sp),
                              color: theme.verseTextColor,
                              height:
                                  isPortrait
                                      ? (pageNumber == 1 || pageNumber == 2)
                                          ? 2.2 * h
                                          : theme.verseHeight * h
                                      : (pageNumber == 1 || pageNumber == 2)
                                      ? 4 *
                                          h // simplified based on user's manual edit evaluation
                                      : 4 *
                                          h, // simplified based on user's manual edit evaluation
                              letterSpacing: theme.letterSpacing,
                              wordSpacing: theme.wordSpacing,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Swipeable Mushaf (604 pages, RTL) built on [NoorQcfPage].
///
/// Mirrors qcf_quran's `PageviewQuran` API used by the reader; the package
/// widget cannot be used because it hard-codes the buggy `QcfPage`.
class NoorQuranPageView extends StatefulWidget {
  /// 1-based initial page number (1..604)
  final int initialPageNumber;

  /// Optional external controller. If not provided, an internal one is created.
  final PageController? controller;

  final double sp;
  final double h;

  /// Optional callback when page changes. Provides 1-based page number.
  final ValueChanged<int>? onPageChanged;

  /// Optional override font size passed to each page.
  final double? fontSize;

  /// Optional theme configuration for customizing all visual aspects.
  final QcfThemeData? theme;

  /// Optional callback to get background color for individual verses.
  final Color? Function(int surahNumber, int verseNumber)? verseBackgroundColor;

  /// Callback when a verse is tapped.
  final void Function(int surahNumber, int verseNumber)? onTap;

  /// Callback when a single WORD is tapped (per-word popup).
  /// Passed through to [NoorQcfPage.onWordTap].
  final void Function(int surahNumber, int verseNumber, int wordIndex)?
  onWordTap;

  /// Custom scroll physics for the PageView.
  final ScrollPhysics? physics;

  const NoorQuranPageView({
    super.key,
    this.initialPageNumber = 1,
    this.controller,
    this.onPageChanged,
    this.fontSize,
    this.sp = 1,
    this.h = 1,
    this.theme,
    this.verseBackgroundColor,
    this.onTap,
    this.onWordTap,
    this.physics,
  }) : assert(initialPageNumber >= 1 && initialPageNumber <= totalPagesCount);

  @override
  State<NoorQuranPageView> createState() => _NoorQuranPageViewState();
}

class _NoorQuranPageViewState extends State<NoorQuranPageView> {
  PageController? _internalController;

  PageController get _controller => widget.controller ?? _internalController!;

  bool get _ownsController => widget.controller == null;

  @override
  void initState() {
    super.initState();
    if (_ownsController) {
      _internalController = PageController(
        initialPage: widget.initialPageNumber - 1,
      );
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _internalController?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTheme = widget.theme ?? const QcfThemeData();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: effectiveTheme.pageBackgroundColor,
        child: PageView.builder(
          physics: widget.physics,
          controller: _controller,
          reverse: false, // right-to-left paging order
          itemCount: totalPagesCount,
          onPageChanged: (index) =>
              widget.onPageChanged?.call(index + 1), // 1-based
          itemBuilder: (context, index) {
            final pageNumber = index + 1; // 1-based page
            return NoorQcfPage(
              pageNumber: pageNumber,
              fontSize: widget.fontSize,
              verseBackgroundColor: widget.verseBackgroundColor,
              onTap: widget.onTap,
              onWordTap: widget.onWordTap,
              sp: widget.sp,
              h: widget.h,
              theme: effectiveTheme,
            );
          },
        ),
      ),
    );
  }
}
