import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qcf_quran/qcf_quran.dart';

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

        // Gesture Handling
        GestureRecognizer? recognizer;
        if (onTap != null) {
          recognizer =
              TapGestureRecognizer()..onTap = () => onTap?.call(surah, v);
        } else if (onLongPress != null ||
            onLongPressDown != null ||
            onLongPressUp != null) {
          final longPressRecognizer = LongPressGestureRecognizer();
          longPressRecognizer.onLongPress = () => onLongPress?.call(surah, v);
          longPressRecognizer.onLongPressStart =
              (d) => onLongPressDown?.call(surah, v, d);
          longPressRecognizer.onLongPressUp =
              () => onLongPressUp?.call(surah, v);
          longPressRecognizer.onLongPressEnd =
              (d) => onLongPressCancel?.call(surah, v);
          recognizer = longPressRecognizer;
        }

        final verseBgColor =
            theme.verseBackgroundColor?.call(surah, v) ??
            verseBackgroundColor?.call(surah, v);

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

        verseSpans.add(
          TextSpan(
            text:
                v == ranges[0]['start']
                    ? "${verseText.substring(0, 1)}\u200A${verseText.substring(1, verseText.length)}"
                    : verseText,
            recognizer: recognizer,
            style:
                verseBgColor != null
                    ? TextStyle(backgroundColor: verseBgColor)
                    : null,
            children: [
              verseNumberSpan,
              if (endsPrintedLine && !isLastVerseOfPage)
                const TextSpan(text: '\n'),
            ],
          ),
        );
      }
    }

    return Stack(
      children: [
        Scrollbar(
          child: SingleChildScrollView(
            child: SizedBox(
              height: screenSize.height,
              width: screenSize.width,
              child: ListView(
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
