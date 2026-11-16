import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import 'quran_audio.dart';

/// Which slice of the Mushaf the player is playing.
enum PlayerScope { word, ayah, page, surah }

/// The audio engine behind the player sheet.
///
/// One ayah file at a time (everyayah.com), advanced manually, so that
/// repeat counts, prev/next, reciter switching and page following all
/// stay under our control. The old whole-surah mp3quran file is gone:
/// the surah scope is the surah's ayah files in sequence.
///
/// Word scope: when the reciter has a Quran.com recitation, the word
/// is played from the reciter's own ayah recording using Quran.com's
/// per-word timestamps (seek to the word start, stop at its end).
/// Otherwise the word comes from Quran.com's word-by-word recording
/// (one fixed voice) — never silently missing.
class AudioPlayerController extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();

  int reciterIndex = 0;
  PlayerScope scope = PlayerScope.page;
  List<(int, int)> queue = [];
  int queueIndex = 0;

  bool isPlaying = false;
  bool isLoading = false;
  bool repeatItem = false;
  bool repeatScope = false;
  /// 0 = endless, otherwise the number of plays.
  int repeatCount = 3;
  double speed = 1.0;
  int fromPage = 1;
  int toPage = 1;

  // Word scope state.
  int? wordIndex; // 1-based position inside the ayah.
  List<WordSegment>? wordSegments;
  bool wordUsesWbw = false;
  int wordCount = 0;

  /// Fired when the playing ayah changes, so the reader can follow
  /// the playback position (jump to the ayah's page).
  void Function((int, int) ayah)? onAyahChanged;

  /// Fired on a playback error with a retry action for the SnackBar.
  void Function(String message, Future<void> Function() retry)? onError;

  int _itemPlays = 0;
  int _scopePlays = 0;
  Duration? _wordEnd;
  bool _wordEndHandled = false;
  int _playToken = 0;
  // The _playToken value whose finish was already handled: the word
  // end (position listener) and the file end (state stream) can both
  // fire for the same item — the second must be ignored.
  int _finishedToken = -1;
  bool _disposed = false;

  (int, int)? get currentAyah =>
      queue.isEmpty ? null : queue[queueIndex];

  Reciter get reciter => reciters[reciterIndex];

  AudioPlayerController() {
    _player.playerStateStream.listen((state) {
      if (_disposed) return;
      final playing = state.playing;
      if (playing != isPlaying) {
        isPlaying = playing;
        notifyListeners();
      }
      if (state.processingState == ProcessingState.completed) {
        _onItemFinished();
      }
    });
    _player.positionStream.listen((position) {
      if (_disposed || _wordEnd == null || _wordEndHandled) return;
      if (position >= _wordEnd!) {
        _wordEndHandled = true;
        _player.pause();
        _onItemFinished();
      }
    });
  }

  /// Sets the reciter without playing or persisting (initial restore).
  void setInitialReciterIndex(int index) {
    reciterIndex = index.clamp(0, reciters.length - 1);
    notifyListeners();
  }

  Future<void> setReciter(int index) async {
    if (index < 0 || index >= reciters.length) return;
    reciterIndex = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reciter_index', index);
    notifyListeners();
    // Rebuild the current item with the new reciter's folder and
    // resume from the same ayah / word, not from the start.
    if (queue.isNotEmpty) {
      await _playCurrent();
    }
  }

  void setRepeatCount(int count) {
    repeatCount = count;
    notifyListeners();
  }

  void toggleRepeatItem() {
    repeatItem = !repeatItem;
    notifyListeners();
  }

  void toggleRepeatScope() {
    repeatScope = !repeatScope;
    notifyListeners();
  }

  Future<void> setSpeed(double value) async {
    speed = value;
    await _player.setSpeed(value);
    notifyListeners();
  }

  Future<void> playWord(int surah, int ayah, int word) async {
    scope = PlayerScope.word;
    queue = [(surah, ayah)];
    queueIndex = 0;
    wordIndex = word;
    wordSegments = null;
    wordUsesWbw = false;
    wordCount = _verseWordCount(surah, ayah);
    _scopePlays = 1;
    await _playCurrent();
  }

  Future<void> playAyah(int surah, int ayah) async {
    scope = PlayerScope.ayah;
    queue = [(surah, ayah)];
    queueIndex = 0;
    wordIndex = null;
    _scopePlays = 1;
    await _playCurrent();
  }

  Future<void> playPages(int from, int to) async {
    scope = PlayerScope.page;
    fromPage = from;
    toPage = to;
    queue = ayahsOfPages(from, to);
    queueIndex = 0;
    wordIndex = null;
    _scopePlays = 1;
    await _playCurrent();
  }

  Future<void> playSurah(int surah) async {
    scope = PlayerScope.surah;
    queue = ayahsOfSurah(surah);
    queueIndex = 0;
    wordIndex = null;
    _scopePlays = 1;
    await _playCurrent();
  }

  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await _player.pause();
      return;
    }
    if (queue.isEmpty) return;
    if (_player.processingState == ProcessingState.completed) {
      await _playCurrent();
    } else {
      await _player.play();
    }
  }

  Future<void> next() async {
    if (scope == PlayerScope.word) {
      await _nextWord();
      return;
    }
    if (queueIndex < queue.length - 1) {
      queueIndex++;
      _itemPlays = 1;
      onAyahChanged?.call(queue[queueIndex]);
      await _playCurrent();
    }
  }

  Future<void> previous() async {
    if (scope == PlayerScope.word) {
      await _previousWord();
      return;
    }
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }
    if (queueIndex > 0) {
      queueIndex--;
      _itemPlays = 1;
      onAyahChanged?.call(queue[queueIndex]);
      await _playCurrent();
    }
  }

  Future<void> stop() async {
    _wordEnd = null;
    await _player.stop();
    if (!_disposed) {
      isPlaying = false;
      notifyListeners();
    }
  }

  // -- internals -------------------------------------------------------

  int _verseWordCount(int surah, int ayah) {
    if (wordSegments != null) return wordSegments!.length;
    return quran
        .getVerse(surah, ayah)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .length;
  }

  Future<void> _nextWord() async {
    final ayah = currentAyah;
    final word = wordIndex;
    if (ayah == null || word == null) return;
    if (word < wordCount) {
      wordIndex = word + 1;
      await _playCurrent();
      return;
    }
    final nextAyah = _adjacentAyah(ayah, 1);
    if (nextAyah == null) return;
    queue = [nextAyah];
    queueIndex = 0;
    wordIndex = 1;
    wordSegments = null;
    wordCount = _verseWordCount(nextAyah.$1, nextAyah.$2);
    onAyahChanged?.call(nextAyah);
    await _playCurrent();
  }

  Future<void> _previousWord() async {
    final ayah = currentAyah;
    final word = wordIndex;
    if (ayah == null || word == null) return;
    if (word > 1) {
      wordIndex = word - 1;
      await _playCurrent();
      return;
    }
    final prevAyah = _adjacentAyah(ayah, -1);
    if (prevAyah == null) return;
    queue = [prevAyah];
    queueIndex = 0;
    wordSegments = null;
    wordCount = _verseWordCount(prevAyah.$1, prevAyah.$2);
    wordIndex = wordCount;
    onAyahChanged?.call(prevAyah);
    await _playCurrent();
  }

  /// The ayah after/before [ayah] in Mushaf order, or null at the ends.
  (int, int)? _adjacentAyah((int, int) ayah, int step) {
    var (surah, verse) = ayah;
    verse += step;
    if (verse < 1) {
      surah -= 1;
      if (surah < 1) return null;
      verse = quran.getVerseCount(surah);
    } else if (verse > quran.getVerseCount(surah)) {
      surah += 1;
      if (surah > 114) return null;
      verse = 1;
    }
    return (surah, verse);
  }

  Future<void> _onItemFinished() async {
    if (_disposed || queue.isEmpty) return;
    if (_finishedToken == _playToken) return;
    _finishedToken = _playToken;
    if (repeatItem && (repeatCount == 0 || _itemPlays < repeatCount)) {
      _itemPlays++;
      await _playCurrent(isReplay: true);
      return;
    }
    if (queueIndex < queue.length - 1) {
      queueIndex++;
      onAyahChanged?.call(queue[queueIndex]);
      await _playCurrent();
      return;
    }
    if (repeatScope && (repeatCount == 0 || _scopePlays < repeatCount)) {
      _scopePlays++;
      queueIndex = 0;
      onAyahChanged?.call(queue[queueIndex]);
      await _playCurrent();
      return;
    }
    await stop();
  }

  Future<void> _playCurrent({bool isReplay = false}) async {
    final ayah = currentAyah;
    if (ayah == null) return;
    final token = ++_playToken;
    if (!isReplay) _itemPlays = 1;
    _wordEnd = null;
    _wordEndHandled = false;
    isLoading = true;
    notifyListeners();

    String url;
    Duration? seekTo;
    try {
      if (scope == PlayerScope.word) {
        final word = wordIndex ?? 1;
        final qcUrl = quranComAyahUrl(reciter, ayah.$1, ayah.$2);
        if (qcUrl != null) {
          wordSegments ??=
              await fetchWordSegments(reciter, ayah.$1, ayah.$2);
          final segments = wordSegments;
          if (segments != null && word - 1 < segments.length) {
            wordCount = segments.length;
            url = qcUrl;
            final seg = segments[word - 1];
            seekTo = Duration(milliseconds: seg.startMs);
            _wordEnd = Duration(milliseconds: seg.endMs);
            wordUsesWbw = false;
          } else {
            url = wbwWordUrl(ayah.$1, ayah.$2, word);
            wordUsesWbw = true;
          }
        } else {
          url = wbwWordUrl(ayah.$1, ayah.$2, word);
          wordUsesWbw = true;
        }
      } else {
        url = everyayahUrl(reciter, ayah.$1, ayah.$2);
      }
      if (token != _playToken || _disposed) return;
      await _player.stop();
      await _player.setLoopMode(LoopMode.off);
      await _player.setUrl(url);
      if (token != _playToken || _disposed) return;
      if (seekTo != null) await _player.seek(seekTo);
      await _player.setSpeed(speed);
      await _player.play();
    } on PlayerException {
      _reportError(_playCurrent);
    } catch (_) {
      _reportError(_playCurrent);
    } finally {
      if (!_disposed) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  void _reportError(Future<void> Function() retry) {
    isPlaying = false;
    notifyListeners();
    onError?.call(
      'الصوت يحتاج إنترنت قوي — تحقق من الاتصال وحاول مجدداً',
      retry,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _player.dispose();
    super.dispose();
  }
}
