import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qcf_quran/qcf_quran.dart';

import 'package:noor_quran/widgets/noor_qcf_page.dart';

bool _noScale() => false;

/// Reader theme used by the app (light), plus a header stand-in.
///
/// The package header contains an InkWell, which cannot find a Material
/// ancestor inside a WidgetSpan placeholder in debug tests
/// (debugCheckHasMaterial; release builds are unaffected, which is why
/// the app works on the phone). This box replicates the real header's
/// layout role exactly: full-width, ~39px tall (mainframe.png 2000x208
/// at width 372), i.e. one line in the page flow.
QcfThemeData _testTheme() => QcfThemeData(
      pageBackgroundColor: const Color(0xFFFAF6EE),
      verseTextColor: const Color(0xFF1A1A1A),
      verseNumberColor: const Color(0xFF8A723D),
      basmalaColor: const Color(0xFF1A1A1A),
      headerTextColor: const Color(0xFF1A1A1A),
      verseHeight: 2.1,
      customHeaderBuilder: (_) => Container(
        width: double.infinity,
        height: 39,
        color: const Color(0xFFFAF6EE),
      ),
    );

/// Faithful replica of SurahReaderScreen's layout WITH the v9 fix:
/// the PageView sits in a LayoutBuilder that computes `h` from the
/// actual viewport height, and the no-scaling MediaQuery wrapper is
/// built from the State's context (above the SafeArea) exactly like
/// the real reader — so it carries the full system padding, and this
/// test proves the page widget handles that (explicit zero padding +
/// viewport-sized box) instead of being pushed down by it.
class _ReaderReplica extends StatefulWidget {
  final int initialPage;
  const _ReaderReplica({required this.initialPage});

  @override
  State<_ReaderReplica> createState() => _ReaderReplicaState();
}

class _ReaderReplicaState extends State<_ReaderReplica> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialPage - 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The State's context sits ABOVE this build's SafeArea, exactly
    // like the real reader — so this MediaQuery carries the full
    // system padding into the PageView subtree.
    final mqData = MediaQuery.of(context);
    final width = mqData.size.width;
    final qcfSp = width / 392.7; // zoom 1.0
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      enableScaleText: _noScale,
      minTextAdapt: true,
      builder: (_, __) => Scaffold(
        backgroundColor: const Color(0xFFFAF6EE),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                          child: SizedBox(
                            key: const Key('header-row'),
                            height: 31,
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: const [
                                SizedBox(
                                    width: 90,
                                    child: Text('الجزء الأول')),
                                SizedBox(
                                    width: 90, child: Text('12:08:20 م')),
                                SizedBox(
                                    width: 90,
                                    child: Text('سورة البقرة')),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final h = mushafHeightFactor(
                                constraints.maxHeight,
                                qcfSp,
                              );
                              return MediaQuery(
                                data: mqData.copyWith(
                                  textScaler: TextScaler.noScaling,
                                ),
                                child: NoorQuranPageView(
                                  key: const Key('page-view'),
                                  controller: _pageController,
                                  initialPageNumber: widget.initialPage,
                                  sp: qcfSp,
                                  h: h,
                                  theme: _testTheme(),
                                ),
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6, top: 4),
                          child: SizedBox(
                            key: const Key('footer-num'),
                            height: 35,
                            child: const Text('٥'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Returns (lineCount, paragraphHeight) for [page] laid out at
/// [pageWidth] with the given [sp] and [h], using the real QCF fonts.
Future<(int, double)> _measurePage(
    WidgetTester tester, int page, double pageWidth, double sp, double h) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ScreenUtilInit(
        designSize: const Size(390, 844),
        enableScaleText: _noScale,
        minTextAdapt: true,
        builder: (_, __) => Scaffold(
          body: NoorQcfPage(
            pageNumber: page,
            sp: sp,
            h: h,
            theme: _testTheme(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  RichText? longestWidget;
  for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
    final span = rt.text;
    if (span is TextSpan) {
      if (longestWidget == null ||
          span.toPlainText().length >
              (longestWidget.text as TextSpan).toPlainText().length) {
        longestWidget = rt;
      }
    }
  }
  if (longestWidget == null) return (0, 0.0);
  final span = longestWidget.text as TextSpan;
  final rp =
      tester.renderObject<RenderParagraph>(find.byWidget(longestWidget));
  final dims = <PlaceholderDimensions>[];
  var child = rp.firstChild;
  while (child != null) {
    dims.add(PlaceholderDimensions(
      size: child.size,
      alignment: PlaceholderAlignment.bottom,
    ));
    child = rp.childAfter(child);
  }
  final painter = TextPainter(
    text: span,
    textDirection: ui.TextDirection.rtl,
    textAlign: TextAlign.center,
    locale: const Locale('ar'),
  )
    ..setPlaceholderDimensions(dims)
    ..layout(maxWidth: pageWidth);
  return (painter.computeLineMetrics().length, painter.height);
}

/// Sets the test view to a phone size with realistic system insets
/// (24dp status bar, 45dp nav bar) and returns the pumped replica's
/// PageView viewport height.
Future<double> _pumpReplica(
    WidgetTester tester, double w, double h, double dpr) async {
  tester.view.physicalSize = Size(w * dpr, h * dpr);
  tester.view.devicePixelRatio = dpr;
  // NOTE: MediaQueryData.fromView reads view.padding, and
  // TestFlutterView keeps padding as its own override — setting
  // viewPadding alone does NOT change padding.
  tester.view.padding =
      FakeViewPadding(top: 24 * dpr, bottom: 45 * dpr);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);

  await tester.pumpWidget(
    const MaterialApp(home: _ReaderReplica(initialPage: 5)));
  await tester.pumpAndSettle();
  return tester.getSize(find.byKey(const Key('page-view'))).height;
}

void main() {
  // Load the real QCF page fonts (see qcf_real_render_test.dart for
  // why this manual registration is needed on Linux).
  setUpAll(() async {
    for (var page = 1; page <= 604; page++) {
      final p = page.toString().padLeft(3, '0');
      final data = await rootBundle.load(
          'packages/qcf_quran/assets/fonts/qcf4/QCF4${p}_X-Regular.woff');
      final loader = FontLoader('packages/qcf_quran/QCF_P$p');
      loader.addFont(Future.value(data));
      await loader.load();
    }
  });

  testWidgets('v9: page 5 shows all 15 lines, no clipping, no scrolling',
      (tester) async {
    for (final (w, h, dpr) in [
      (411.0, 919.0, 2.625),
      (432.0, 965.0, 2.5),
    ]) {
      final viewportHeight = await _pumpReplica(tester, w, h, dpr);
      final sp = w / 392.7;
      final factor = mushafHeightFactor(viewportHeight, sp);

      final pvTop = tester.getTopLeft(find.byKey(const Key('page-view'))).dy;
      final pvBottom = pvTop + viewportHeight;

      // The page's RichText (longest text span).
      RichText? longestWidget;
      for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
        final span = rt.text;
        if (span is TextSpan) {
          if (longestWidget == null ||
              span.toPlainText().length >
                  (longestWidget.text as TextSpan).toPlainText().length) {
            longestWidget = rt;
          }
        }
      }
      expect(longestWidget, isNotNull);
      final rtTop =
          tester.getTopLeft(find.byWidget(longestWidget!)).dy;
      final rtSize = tester.getSize(find.byWidget(longestWidget));
      // The text starts exactly at the viewport top (v8 bug: it was
      // pushed down 24dp by the status-bar padding) and ends inside
      // the viewport (v8 bug: line 14 half-clipped, line 15 missing).
      expect(rtTop, closeTo(pvTop, 0.5),
          reason: '$w x $h: text must start at viewport top');
      expect(rtTop + rtSize.height, lessThanOrEqualTo(pvBottom + 0.5),
          reason: '$w x $h: text must end inside the viewport');

      // No scrolling anywhere in the page: the scroll view's child
      // is exactly the viewport height (v8 bug: it was the full
      // screen height, maxScrollExtent 133dp). SingleChildScrollView
      // is stateless; its own Scrollable (the first Scrollable
      // descendant — the inner ListView's comes later) holds the
      // position.
      for (final scsv in find.byType(SingleChildScrollView).evaluate()) {
        final scrollable = find.descendant(
          of: find.byWidget(scsv.widget),
          matching: find.byType(Scrollable),
        );
        final state = tester.state<ScrollableState>(scrollable.first);
        expect(state.position.maxScrollExtent, 0.0,
            reason: '$w x $h: page must not scroll');
      }

      // And it is still 15 lines at the computed factor.
      final (lines, height) = await _measurePage(tester, 5, w, sp, factor);
      expect(lines, 15, reason: '$w x $h: page 5 must be 15 lines');
      expect(height, lessThanOrEqualTo(viewportHeight + 0.5));
    }
  });

  testWidgets('v9: all 604 pages fit vertically at 3 phone sizes',
      (tester) async {
    for (final (w, h, dpr) in [
      (411.0, 919.0, 2.625),
      (432.0, 965.0, 2.5),
      (390.0, 844.0, 2.0),
    ]) {
      final viewportHeight = await _pumpReplica(tester, w, h, dpr);
      final sp = w / 392.7;
      final factor = mushafHeightFactor(viewportHeight, sp);
      expect(factor, lessThanOrEqualTo(1.0));
      expect(factor, greaterThan(0.85),
          reason: '$w x $h: factor $factor shrinks lines too much');

      final deviations = <String>[];
      for (var page = 1; page <= 604; page++) {
        final (lines, height) =
            await _measurePage(tester, page, w, sp, factor);
        final expected = page <= 2 ? 8 : 15;
        if (lines != expected) {
          deviations.add('page $page: lines=$lines expected=$expected');
        } else if (height > viewportHeight + 0.5) {
          deviations.add(
              'page $page: height=$height > viewport=$viewportHeight');
        }
      }
      expect(deviations, isEmpty,
          reason: '$w x $h: pages not fitting: ${deviations.join('; ')}');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
