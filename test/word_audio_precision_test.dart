import 'package:flutter_test/flutter_test.dart';

import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/quran_audio.dart';

/// v12 word-audio precision (user's explicit requirement): a tapped
/// word must play EXACTLY and COMPLETELY — just the word, fully
/// pronounced, not cut off at the start or end, never jumping to the
/// ayah's beginning or end.
///
/// The controller pads the Quran.com segment boundaries: the seek
/// lands slightly BEFORE the segment start and playback runs slightly
/// PAST the segment end. These tests pin the window arithmetic.
/// Real playback (seek accuracy, pause latency) still needs the
/// device — just_audio has no audio platform in a unit test.
void main() {
  test('paddedWordWindow: start early, end late', () {
    final (seekTo, end) =
        AudioPlayerController.paddedWordWindow(const WordSegment(1000, 2000));
    expect(seekTo, const Duration(milliseconds: 880));
    expect(end, const Duration(milliseconds: 2150));
  });

  test('paddedWordWindow: real 2:33 first word (850–1760)', () {
    final (seekTo, end) =
        AudioPlayerController.paddedWordWindow(const WordSegment(850, 1760));
    expect(seekTo, const Duration(milliseconds: 730));
    expect(end, const Duration(milliseconds: 1910));
  });

  test('paddedWordWindow: start clamps at zero for the first word', () {
    final (seekTo, end) =
        AudioPlayerController.paddedWordWindow(const WordSegment(50, 900));
    expect(seekTo, Duration.zero);
    expect(end, const Duration(milliseconds: 1050));
  });

  test('paddedWordWindow: padding constants are small, not ayah-wide', () {
    // A 120/150 ms pad cannot swallow a neighbouring word or reach
    // the ayah's start/end for any real segment (words are hundreds
    // of ms apart; the shortest real segments are ~200 ms).
    expect(AudioPlayerController.wordPadStartMs, lessThan(200));
    expect(AudioPlayerController.wordPadEndMs, lessThan(200));
  });
}
