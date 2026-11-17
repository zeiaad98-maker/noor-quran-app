import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_downloads.dart';
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
/// Word scope: when the word-voice reciter (the selected reciter if
/// Quran.com carries it, otherwise محمود الحصري — see
/// [wordVoiceReciterIndex]) has a Quran.com recitation, the word is
/// played from that reciter's own ayah recording using Quran.com's
/// per-word timestamps (seek to the word start, stop at its end).
/// Only if that fails too does the word come from Quran.com's
/// word-by-word recording (one fixed voice) — never silently missing.
class AudioPlayerController extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();

  /// Offline downloads (v12, optional): when a downloaded ayah file
  /// exists for the current reciter, the player plays it instead of
  /// streaming — same recording (everyayah), so word-segment timings
  /// still apply. Null in tests / when downloads are not wired up.
  final AudioDownloadService? downloads;

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

  /// v13.1: true when the word is playing in محمود الحصري's voice
  /// because the selected reciter has no Quran.com word segments
  /// (الطنيجي + 5 others) — shown honestly in the player sheet, so
  /// the user is never told the word is in the selected reciter's
  /// voice when it is Husary's. False when the word plays in the
  /// selected reciter's own voice, and false when it fell back to
  /// the wbw recording ([wordUsesWbw] covers that case).
  bool wordUsesHusaryFallback = false;
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

  /// True only once the current word has actually started playing.
  /// The position stream can replay the PREVIOUS play's position
  /// during the next play's load (just_audio re-emits the last
  /// playback event while activating) — that stale position is
  /// already past the new word's end, so an unguarded listener
  /// fires on it, marks the word handled, and the new play's own
  /// finish then never fires (the word gets stuck after one
  /// repeat — verified in tests, v13.1). The listener stays
  /// disarmed until this word's file really plays.
  bool _wordArmed = false;
  int _playToken = 0;
  // The _playToken value whose finish was already handled: the word
  // end (position listener) and the file end (state stream) can both
  // fire for the same item — the second must be ignored.
  int _finishedToken = -1;

  /// True while one finish is being handled (a replay / advance /
  /// stop is in flight). The two listeners can fire for the same
  /// item end — and the platform can emit the completed state twice
  /// (playing true→false) — so a duplicate finish must be ignored
  /// even though the replay it triggered already advanced
  /// [_playToken] (the [_finishedToken] check alone races with
  /// that: the replay's `_playCurrent` increments the token
  /// synchronously, so the duplicate looks like a new finish,
  /// consumes a repeat count and kills the replay — verified in
  /// tests, v13.1). Cleared when the handling returns, i.e. once
  /// the next item has started (or failed to) or playback stopped.
  bool _handlingFinish = false;

  /// Word-playback padding (v12 precision fix — the user's explicit
  /// requirement: a tapped word must play EXACTLY and COMPLETELY).
  /// The seek lands this far BEFORE the segment start so the first
  /// letter is never cut by seek inaccuracy, and playback runs this
  /// far PAST the segment end so the last letter finishes. Small
  /// enough (120/150 ms) not to swallow a neighbouring word: Quran.com
  /// segments leave a gap between words, and the padded end still
  /// stops well before the next word starts in normal recitation.
  static const int wordPadStartMs = 120;
  static const int wordPadEndMs = 150;

  /// Extra end padding for the LAST word of an ayah (v13): there is
  /// no next word to swallow, and the final word's decay runs past
  /// its segment end (verified on Husary 2:33: the last word's sound
  /// ends ~90 ms after the padded end, i.e. its tail was cut). 400 ms
  /// covers the decay with margin; the file's trailing silence
  /// absorbs the rest, and the file-completed state ends playback
  /// if the window ever runs past the file.
  static const int wordPadEndLastWordMs = 400;

  /// Padded playback window for one word segment: (seekTo, end).
  /// The start is clamped at zero (the first word of an ayah).
  /// The last word of an ayah gets the longer end padding (there is
  /// no next word after it). Pure, so it is pinned by unit tests.
  static (Duration, Duration) paddedWordWindow(
    WordSegment seg, {
    bool isLastWord = false,
  }) {
    final startMs = seg.startMs - wordPadStartMs;
    final endMs =
        seg.endMs + (isLastWord ? wordPadEndLastWordMs : wordPadEndMs);
    return (
      Duration(milliseconds: startMs < 0 ? 0 : startMs),
      Duration(milliseconds: endMs),
    );
  }

  bool _disposed = false;

  (int, int)? get currentAyah => queue.isEmpty ? null : queue[queueIndex];

  Reciter get reciter => reciters[reciterIndex];

  AudioPlayerController({this.downloads}) {
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
    _player.positionStream.listen((position) async {
      if (_disposed ||
          _wordEnd == null ||
          !_wordArmed ||
          _wordEndHandled) {
        return;
      }
      if (position >= _wordEnd!) {
        _wordEndHandled = true;
        // Await the pause BEFORE finishing: the pause's platform
        // call must land before the replay's play(), otherwise the
        // stale pause resumes after the replay started and pauses
        // the NEW play instead (and cancels its finish in tests,
        // where every step is microtask-fast — on a device the
        // replay's load is slower, but awaiting is correct there
        // too). A failed pause must not lose the finish.
        try {
          await _player.pause();
        } catch (_) {}
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
    // Word segments belong to the WORD-voice reciter, which follows
    // the selected reciter (own voice, or Husary fallback) — a stale
    // list from the previous reciter would time the new reciter's
    // file with the old reciter's timestamps. Drop it; the word
    // path re-resolves it for the new reciter.
    if (scope == PlayerScope.word) wordSegments = null;
    // Rebuild the current item with the new reciter's folder and
    // resume from the same ayah / word, not from the start.
    if (queue.isNotEmpty) {
      await _playCurrent();
    }
  }

  /// Pure repeat decision, pinned by unit tests: [repeatCount] 0 =
  /// endless, otherwise the item / scope replays until it has played
  /// that many times in total — [plays] counts the play that just
  /// finished, starting at 1. (So count 3 replays after plays 1 and
  /// 2, and stops after play 3; count 1 never replays.)
  static bool shouldRepeat({
    required bool enabled,
    required int repeatCount,
    required int plays,
  }) =>
      enabled && (repeatCount == 0 || plays < repeatCount);

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
    wordUsesHusaryFallback = false;
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

  /// Replays the current item from its start, whether it is playing
  /// or already finished (the mini bar's replay button). A manual
  /// replay restarts the repeat count: the replayed play is play 1
  /// again, so a repeat count of 3 still means 3 plays from here.
  /// A no-op with an empty queue (safe to tap before anything plays).
  Future<void> replayCurrent() async {
    if (queue.isEmpty) return;
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
    _wordArmed = false;
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
    if (_handlingFinish) return;
    if (_finishedToken == _playToken) return;
    _finishedToken = _playToken;
    _handlingFinish = true;
    try {
      if (shouldRepeat(
          enabled: repeatItem,
          repeatCount: repeatCount,
          plays: _itemPlays)) {
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
      if (shouldRepeat(
          enabled: repeatScope,
          repeatCount: repeatCount,
          plays: _scopePlays)) {
        _scopePlays++;
        queueIndex = 0;
        onAyahChanged?.call(queue[queueIndex]);
        await _playCurrent();
        return;
      }
      await stop();
    } finally {
      _handlingFinish = false;
    }
  }

  Future<void> _playCurrent({bool isReplay = false}) async {
    final ayah = currentAyah;
    if (ayah == null) return;
    final token = ++_playToken;
    if (!isReplay) _itemPlays = 1;
    _wordEnd = null;
    _wordEndHandled = false;
    _wordArmed = false;
    lastError = null;
    isLoading = true;
    notifyListeners();

    try {
      if (scope == PlayerScope.word) {
        await _playWordCurrent(token, ayah);
      } else {
        // Cache-on-play (v13): the ayah file is downloaded once and
        // played from disk after that — clear, pure and complete on
        // a weak connection, instant on repeat, offline after.
        // A failed download falls back to streaming below.
        final url = everyayahUrl(reciter, ayah.$1, ayah.$2);
        final local = await downloads?.cacheAyahFile(reciter, ayah.$1, ayah.$2);
        if (token != _playToken || _disposed) return;
        await _player.stop();
        await _player.setLoopMode(LoopMode.off);
        // Bounded: the old bare setUrl could hang forever on a
        // stalled connection, leaving the spinner up with no sound
        // and no error.
        if (local != null) {
          await _player
              .setFilePath(local.path)
              .timeout(const Duration(seconds: 20));
        } else {
          await _player.setUrl(url).timeout(const Duration(seconds: 20));
        }
        if (token != _playToken || _disposed) return;
        await _player.setSpeed(speed);
        await _player.play();
        // Prefetch the next ayah while this one plays, so page /
        // surah playback has no gap between ayahs on a weak
        // connection. Best-effort: failures are ignored, the next
        // play falls back to streaming.
        final dl = downloads;
        if (dl != null && queueIndex + 1 < queue.length) {
          final nextAyah = queue[queueIndex + 1];
          unawaited(
            dl.cacheAyahFile(reciter, nextAyah.$1, nextAyah.$2).then((_) {}),
          );
        }
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
  /// word is played from the word-voice reciter's ayah recording.
  /// Every step is time-boxed.
  ///
  /// Word voice (v13.1): the selected reciter when Quran.com
  /// carries it, otherwise محمود الحصري ([wordVoiceReciterIndex]) —
  /// his own real voice, clear and complete. The AYAH scope still
  /// uses the SELECTED reciter (see _playCurrent); only this word
  /// path resolves the fallback.
  ///
  /// Cache-on-play (v13): the ayah file is downloaded once and the
  /// segment is played from the LOCAL file — no streaming stutter,
  /// no start-late on a weak connection, instant on repeat. For the
  /// Husary fallback the HUSARY ayah file is the one cached
  /// (`cacheAyahFile(reciters[0], ...)`), so the word plays from
  /// disk in Husary's voice. A stalled download falls back to
  /// streaming the ayah file, then to the small wbw word file
  /// (43–102 KB, no seek, starts at 0), which is itself cached
  /// after its first download — wbw is the LAST resort only, when
  /// the Husary file cannot be fetched either.
  Future<void> _playWordCurrent(int token, (int, int) ayah) async {
    final word = wordIndex ?? 1;
    final wordReciterIndex = wordVoiceReciterIndex(reciterIndex);
    final wordReciter = reciters[wordReciterIndex];
    final qcUrl = quranComAyahUrl(wordReciter, ayah.$1, ayah.$2);
    if (qcUrl != null) {
      wordSegments ??=
          await wordSegmentsFor(wordReciter, ayah.$1, ayah.$2);
      final segments = wordSegments;
      if (segments != null && word - 1 < segments.length) {
        wordCount = segments.length;
        final seg = segments[word - 1];
        // Padded window (v12): start slightly early, end slightly
        // late — the word plays completely, never cut at either end,
        // and never jumps to the ayah's beginning or end. The last
        // word gets the longer end padding (v13): its decay runs
        // past the segment end and there is no next word to swallow.
        // v13.1 re-verified on REAL Husary audio (1:1, 2:33, 2:255,
        // 112:1 — all 80 words): worst start margin +50 ms at
        // -40 dBFS, worst true end margin +200 ms, no word cut, so
        // the 120/150/400 ms padding is kept, not widened (a wider
        // start pad would swallow more of the previous word).
        final (seekTo, wordEnd) = paddedWordWindow(
          seg,
          isLastWord: word >= segments.length,
        );
        _wordEnd = wordEnd;
        wordUsesWbw = false;
        wordUsesHusaryFallback = wordReciterIndex != reciterIndex;
        if (token != _playToken || _disposed) return;
        await _player.stop();
        await _player.setLoopMode(LoopMode.off);
        // Downloaded file first (offline): the word-voice reciter's
        // everyayah recording, which the segments were timed
        // against. For Husary the cached everyayah file is
        // byte-identical to the Quran.com file (verified 2026-11-17,
        // md5 5383bd2d… for 2:33), so the timings transfer exactly;
        // for the other segment reciters it is the same recording
        // at a different bitrate, inside the padding. A corrupt
        // local file falls through to streaming, then to wbw below.
        var played = false;
        final local =
            await downloads?.cacheAyahFile(wordReciter, ayah.$1, ayah.$2);
        if (token != _playToken || _disposed) return;
        if (local != null) played = await _loadLocal(local, seekTo);
        if (!played) played = await _loadAndPlay(qcUrl, seekTo);
        if (played) {
          // The word really plays now: arm the position listener
          // (see [_wordArmed] — stale positions during the load
          // above must not count as this word's end).
          _wordArmed = true;
          return;
        }
        // Ayah file stalled: fall through to the wbw file below.
        // The seek/end state belongs to the ayah file — reset it so
        // the position listener cannot cut the wbw file short.
        _wordEnd = null;
        _wordEndHandled = false;
      }
    }
    // No segments (one of the 18 bundle gaps, or API + cache both
    // failed) or the ayah file stalled: the small wbw word
    // recording — cached on first download, played from disk after
    // that. This is the last resort, not the Husary fallback: the
    // word is NOT in Husary's voice here, and the sheet says so.
    wordUsesWbw = true;
    wordUsesHusaryFallback = false;
    if (token != _playToken || _disposed) return;
    await _player.stop();
    await _player.setLoopMode(LoopMode.off);
    final wbwLocal = await downloads?.cacheWbwFile(ayah.$1, ayah.$2, word);
    if (token != _playToken || _disposed) return;
    final ok = wbwLocal != null
        ? await _loadLocal(wbwLocal, Duration.zero)
        : await _loadAndPlay(
            wbwWordUrl(ayah.$1, ayah.$2, word),
            Duration.zero,
          );
    if (!ok) _reportError(_playCurrent);
  }

  /// Same as [_loadAndPlay] but for a downloaded local file
  /// (setFilePath instead of setUrl). Returns false on any error so
  /// the caller can fall back to streaming.
  Future<bool> _loadLocal(File file, Duration seekTo) async {
    try {
      await _player.setFilePath(file.path).timeout(const Duration(seconds: 10));
      await _player.seek(seekTo).timeout(const Duration(seconds: 5));
      await _player.setSpeed(speed);
      await _player.play();
      return await _waitForPositionBeyond(seekTo);
    } catch (_) {
      return false;
    }
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
    lastError = 'تعذّر تشغيل الصوت — تحقق من الاتصال بالإنترنت وحاول مجدداً';
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
