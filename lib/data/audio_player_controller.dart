import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import 'quran_audio.dart';
import 'word_meanings.dart';

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
  bool isMuted = false;
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

  /// Last playback error, shown INSIDE the player sheet (the old
  /// SnackBar-only error was hidden behind the modal sheet, so a
  /// failed word tap looked like nothing happening at all).
  String? lastError;

  /// Retries the item that failed (clears [lastError] first).
  Future<void> retryLastError() async {
    if (lastError == null) return;
    lastError = null;
    notifyListeners();
    await _playCurrent();
  }

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
    wordCount = await _verseWordCount(surah, ayah);
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
    // Invalidate any in-flight _playCurrent: without this, a load
    // that finishes after the user closed the sheet would seek + play
    // with no UI at all (ghost audio), and its finally{} would clear
    // the next load's spinner.
    _playToken++;
    _wordEnd = null;
    await _player.stop();
    if (!_disposed) {
      isPlaying = false;
      notifyListeners();
    }
  }

  /// Mutes / unmutes the player (the word popup's mute button).
  /// Just sets the volume to 0 / back to 1 — the playback position
  /// and state are untouched, so unmuting resumes the sound in place.
  Future<void> toggleMute() async {
    isMuted = !isMuted;
    await _player.setVolume(isMuted ? 0.0 : 1.0);
    notifyListeners();
  }

  // -- internals -------------------------------------------------------

  /// Word count of an ayah in AUDIO numbering (Quran.com segments /
  /// wbw files), i.e. the Uthmani word list — NOT the simple-text
  /// split, which counts extra tokens (see wordsForAyah). Used as the
  /// bound for next/previous word, so it can never walk past the last
  /// audio file and 404.
  Future<int> _verseWordCount(int surah, int ayah) async {
    if (wordSegments != null) return wordSegments!.length;
    final words = await QuranWordData.wordsForAyah(surah, ayah);
    return words.length;
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
    wordCount = await _verseWordCount(nextAyah.$1, nextAyah.$2);
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
    wordCount = await _verseWordCount(prevAyah.$1, prevAyah.$2);
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
    lastError = null;
    isLoading = true;
    notifyListeners();

    try {
      if (scope == PlayerScope.word) {
        await _playWordCurrent(token, ayah);
      } else {
        final url = everyayahUrl(reciter, ayah.$1, ayah.$2);
        if (token != _playToken || _disposed) return;
        await _player.stop();
        await _player.setLoopMode(LoopMode.off);
        // Bounded: the old bare setUrl could hang forever on a
        // stalled connection, leaving the spinner up with no sound
        // and no error.
        await _player
            .setUrl(url)
            .timeout(const Duration(seconds: 20));
        if (token != _playToken || _disposed) return;
        await _player.setSpeed(speed);
        await _player.play();
      }
    } on TimeoutException {
      _reportError(_playCurrent);
    } on PlayerException {
      _reportError(_playCurrent);
    } catch (_) {
      _reportError(_playCurrent);
    } finally {
      // A stale token's finally must not clear the newer load's
      // spinner (the old code did, so the spinner vanished while
      // the new word was still loading).
      if (!_disposed && token == _playToken) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Word scope: segments come from the bundle / cache / API
  /// (wordSegmentsFor — no per-tap API wait for Husary), then the
  /// word is played from the reciter's own ayah recording. Every
  /// step is time-boxed, and a stalled ayah file falls back to the
  /// small wbw word file (43–102 KB, no seek, starts at 0) instead
  /// of spinning forever: on a 20 KB/s connection the full 408 KB
  /// ayah file needs ~18 s before a late word can sound, while the
  /// wbw file needs ~1–4 s.
  Future<void> _playWordCurrent(int token, (int, int) ayah) async {
    final word = wordIndex ?? 1;
    final qcUrl = quranComAyahUrl(reciter, ayah.$1, ayah.$2);
    if (qcUrl != null) {
      wordSegments ??=
          await wordSegmentsFor(reciter, ayah.$1, ayah.$2);
      final segments = wordSegments;
      if (segments != null && word - 1 < segments.length) {
        wordCount = segments.length;
        final seg = segments[word - 1];
        final seekTo = Duration(milliseconds: seg.startMs);
        _wordEnd = Duration(milliseconds: seg.endMs);
        wordUsesWbw = false;
        if (token != _playToken || _disposed) return;
        await _player.stop();
        await _player.setLoopMode(LoopMode.off);
        if (await _loadAndPlay(qcUrl, seekTo)) return;
        // Ayah file stalled: fall through to the wbw file below.
        // The seek/end state belongs to the ayah file — reset it so
        // the position listener cannot cut the wbw file short.
        _wordEnd = null;
        _wordEndHandled = false;
      }
    }
    // No segments (reciter without them, one of the 18 bundle gaps,
    // or API + cache both failed) or the ayah file stalled: the
    // small wbw word recording.
    wordUsesWbw = true;
    if (token != _playToken || _disposed) return;
    await _player.stop();
    await _player.setLoopMode(LoopMode.off);
    final ok = await _loadAndPlay(
      wbwWordUrl(ayah.$1, ayah.$2, word),
      Duration.zero,
    );
    if (!ok) _reportError(_playCurrent);
  }

  /// Loads [url], seeks when [seekTo] is given, plays, and waits
  /// until the position actually moves past the seek point — a
  /// stalled buffer leaves the position frozen, which is exactly
  /// the "spinner forever, no sound" failure. Returns false on any
  /// timeout or error instead of throwing; the caller decides the
  /// fallback. The token is checked by the caller.
  Future<bool> _loadAndPlay(String url, Duration seekTo) async {
    try {
      await _player.setUrl(url).timeout(const Duration(seconds: 10));
      await _player.seek(seekTo).timeout(const Duration(seconds: 5));
      await _player.setSpeed(speed);
      await _player.play();
      return await _waitForPositionBeyond(seekTo);
    } catch (_) {
      return false;
    }
  }

  /// True once the player position has moved past [target] (+100 ms
  /// of slack), or the item already finished (a very short word can
  /// complete before the first position event arrives — it did play).
  /// False after 6 s with no movement (buffering stall). The timer
  /// lives inside, so timing out cannot leak the subscription.
  Future<bool> _waitForPositionBeyond(Duration target) async {
    final beyond = target + const Duration(milliseconds: 100);
    if (_player.position > beyond ||
        _player.processingState == ProcessingState.completed) {
      return true;
    }
    final completer = Completer<bool>();
    void done(bool value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    late final StreamSubscription<Duration> sub;
    sub = _player.positionStream.listen((position) {
      if (position > beyond) done(true);
    });
    final timer = Timer(const Duration(seconds: 6), () => done(false));
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  void _reportError(Future<void> Function() retry) {
    isPlaying = false;
    lastError =
        'تعذّر تشغيل الصوت — تحقق من الاتصال بالإنترنت وحاول مجدداً';
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
