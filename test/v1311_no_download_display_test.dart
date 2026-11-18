import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/widgets/audio_player_sheet.dart';

import 'fake_just_audio.dart';

/// v13.11 — the user's choice (Wed 2026-11-18, «ما يبين التحميل أبداً»):
/// while an ayah loads, the player sheet shows NO download display at
/// all — no "جارٍ التحميل…" text, no progress bar, no percent, no
/// Cancel button. The play button's white spinner inside it is the
/// only loading sign; the ✕ button still stops a stuck load.
/// (v13.3's honest-progress row was removed, not hidden.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installFakeJustAudio();

  Future<void> pumpSheet(
      WidgetTester tester, AudioPlayerController controller) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(0.7),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: AudioPlayerSheet(
            controller: controller,
            currentPage: 1,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('loading shows no download text, bar, percent or cancel',
      (tester) async {
    final controller = AudioPlayerController();
    addTearDown(controller.dispose);
    controller.isLoading = true;
    controller.downloadProgress = 0.5;

    await pumpSheet(tester, controller);

    expect(find.text('جارٍ التحميل…'), findsNothing,
        reason: 'no loading text while an ayah downloads');
    expect(find.byType(LinearProgressIndicator), findsNothing,
        reason: 'no progress bar while an ayah downloads');
    expect(find.text('50٪'), findsNothing,
        reason: 'no percent while an ayah downloads');
    expect(find.text('إلغاء'), findsNothing,
        reason: 'no cancel button — the loading row is gone');
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: 'the play button spinner is the only loading sign');
  });

  testWidgets('loading with no reported length also shows nothing',
      (tester) async {
    final controller = AudioPlayerController();
    addTearDown(controller.dispose);
    controller.isLoading = true;
    controller.downloadProgress = null;

    await pumpSheet(tester, controller);

    expect(find.text('جارٍ التحميل…'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('idle sheet still shows the play button', (tester) async {
    final controller = AudioPlayerController();
    addTearDown(controller.dispose);

    await pumpSheet(tester, controller);

    expect(find.byIcon(Icons.play_arrow), findsWidgets,
        reason: 'a play icon is shown (main button + scope body)');
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
