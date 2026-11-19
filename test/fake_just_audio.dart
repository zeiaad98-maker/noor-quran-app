import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

/// Minimal fake just_audio platform for tests.
///
/// just_audio has NO audio platform in flutter_test (see the v9 note
/// in test/word_audio_test.dart): calling the real player hangs or
/// throws unhandled MissingPluginExceptions. This fake implements
/// only what [AudioPlayerController] touches, and simulates playback
/// well enough for the controller's own logic to run end to end:
/// * [FakeAudioPlayerPlatform.load] records the URI and reports a
///   60 s duration, then emits a `ready` event (unblocks
///   `AudioPlayer._load`, which waits for a non-loading state).
/// * [FakeAudioPlayerPlatform.play] nudges the position 250 ms past
///   the seek point (so the controller's `_waitForPositionBeyond`
///   passes at once) and, 100 ms later, finishes the item with
///   exactly ONE trigger — mirroring real playback, where a word
///   ends by the position crossing the word end (the file never
///   completes, playback pauses at the word end) and an ayah ends
///   by a single completed state:
///   * word scope (a seek happened since load): the position jumps
///     5 s forward with a `ready` event — the position listener
///     fires, the state stream does not emit `completed`;
///   * ayah / page / surah scope (no seek): a single `completed`
///     event — no separate playing=false event, so the state stream
///     emits `completed` exactly once. (The real platform can emit
///     it twice, playing true→false; the controller's
///     `_handlingFinish` guard covers that — this fake does not
///     manufacture the duplicate.)
/// * `pause` / `seek` / `stop` (via platform dispose) cancel the
///   pending jump, so a stopped item never finishes late.
///
/// Install once per test file, before any controller is created:
/// ```dart
/// void main() {
///   TestWidgetsFlutterBinding.ensureInitialized();
///   installFakeJustAudio();
///   ...
/// }
/// ```
/// The audio-session channel is mocked the same way just_audio's own
/// test suite does (every call returns null).
FakeJustAudioPlatform installFakeJustAudio() {
  final fake = FakeJustAudioPlatform();
  JustAudioPlatform.instance = fake;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.ryanheise.audio_session'),
    (MethodCall methodCall) async => null,
  );
  return fake;
}

/// The fake platform factory: every [init] creates a NEW
/// [FakeAudioPlayerPlatform] for that player (like the real
/// platform, which has one native player per [AudioPlayer]). Sharing
/// one platform across players leaks events into disposed players'
/// subscriptions ("Cannot add new events after calling close").
/// [player] is the most recently created one — each test creates
/// one controller, so it is the test's player. [autoFinish] is the
/// default for players created after it is set: false means plays
/// complete without ever finishing (for tests that only care about
/// one play).
class FakeJustAudioPlatform extends JustAudioPlatform {
  final List<FakeAudioPlayerPlatform> players = [];

  bool autoFinish = true;

  /// Load-failure injection (v13.2, for fallback-chain tests): any
  /// load whose URI contains one of these substrings throws a
  /// PlatformException, like the real platform on a failed load.
  /// The URI is still recorded in [loadUris] first, so the test can
  /// assert the attempt happened.
  final Set<String> failLoadSubstrings = {};

  /// Play-failure injection (v13.16, for the poisoned-cache test):
  /// the next [failPlayCount] play() calls throw a
  /// TimeoutException, like the real platform hanging on a corrupt
  /// local file — then plays succeed again. Lets a test prove the
  /// controller deletes the bad file and falls back to streaming.
  /// Shared across every platform player the factory creates:
  /// just_audio creates a fresh platform player per load after a
  /// stop, so the count lives in one box ([_failPlayBox]) and is
  /// spent once overall — not once per player.
  int get failPlayCount => _failPlayBox.count;
  set failPlayCount(int value) => _failPlayBox.count = value;
  final _failPlayBox = FailPlayBox();

  /// Artificial delay for every [FakeAudioPlayerPlatform.load]
  /// (v13.2, for race tests): a slow load lets the test inject a
  /// stale finish / a stop mid-load and prove the controller handles
  /// it — the real load is instant in the fake.
  Duration loadDelay = Duration.zero;

  /// Delay before the first position movement after [FakeAudioPlayerPlatform.play]
  /// (v13.17 weakest-net test): a slow-but-progressing stream whose
  /// position first moves only after this long. The nudge is
  /// scheduled, not awaited — play() still returns at once, so the
  /// controller's _waitForPositionBeyond is what waits for the
  /// movement (the 30 s stall window under test).
  Duration movePositionAfter = Duration.zero;

  FakeAudioPlayerPlatform get player => players.last;

  /// Total loads across ALL players created so far (just_audio
  /// re-inits the platform on every activation, so each replay
  /// creates a new player — the latest player's counter alone
  /// would always read 1). Call [resetCounts] in setUp so each
  /// test counts only its own plays.
  int get loadCount =>
      players.fold<int>(0, (sum, p) => sum + p.loadCount);

  List<String> get loadUris => [
        for (final p in players) ...p.loadUris,
      ];

  /// Forgets the players created by earlier tests (they are already
  /// disposed; this only clears the counters).
  void resetCounts() => players.clear();

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final created = FakeAudioPlayerPlatform(
      'fake-${players.length}',
      autoFinish: autoFinish,
      failLoadSubstrings: failLoadSubstrings,
      loadDelay: loadDelay,
      movePositionAfter: movePositionAfter,
      failPlayBox: _failPlayBox,
    );
    players.add(created);
    return created;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async =>
      DisposePlayerResponse();

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async =>
      DisposeAllPlayersResponse();
}

/// Shared mutable counter for injected play() failures (v13.16).
/// The factory hands the SAME box to every platform player it
/// creates, so "fail the next N plays" means N across all players.
class FailPlayBox {
  int count = 0;
}

class FakeAudioPlayerPlatform extends AudioPlayerPlatform {
  FakeAudioPlayerPlatform(super.id,
      {required this.autoFinish,
      required this.failLoadSubstrings,
      this.loadDelay = Duration.zero,
      this.movePositionAfter = Duration.zero,
      required this.failPlayBox});

  final _playbackEvents = StreamController<PlaybackEventMessage>.broadcast();
  final _playerData = StreamController<PlayerDataMessage>.broadcast();

  /// Artificial delay applied at the start of every [load] (see the
  /// factory's [FakeJustAudioPlatform.loadDelay]). Mutable, so a test
  /// can slow a load down after the player was created.
  Duration loadDelay;

  /// Delay before the first position movement after [play] (see the
  /// factory's [FakeJustAudioPlatform.movePositionAfter]). Mutable, so
  /// a test can slow one play down after the player was created.
  Duration movePositionAfter;

  Duration position = Duration.zero;
  Duration duration = const Duration(seconds: 60);
  bool playing = false;

  /// Substrings of URIs whose load must fail (shared with the
  /// factory — see [FakeJustAudioPlatform.failLoadSubstrings]).
  final Set<String> failLoadSubstrings;

  /// Remaining injected play() failures (v13.16 — shared box,
  /// see [FakeJustAudioPlatform.failPlayCount]).
  final FailPlayBox failPlayBox;

  /// True once a seek happened since the last load — i.e. this play
  /// is a word play (the ayah scope never seeks). Decides which
  /// single trigger finishes the item (see the class doc).
  bool _seekedSinceLoad = false;

  /// When false, [play] completes the load but never finishes the
  /// item (no completion event) — for tests that drive the finish
  /// themselves or only care about one play.
  final bool autoFinish;

  /// One entry per [load] call, in order — i.e. one per play attempt
  /// the controller made (the word path loads once per attempt when
  /// the fake succeeds; the wbw fallback would add a second load).
  int loadCount = 0;
  final List<String> loadUris = [];

  Timer? _finishTimer;
  Timer? _moveTimer;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      _playbackEvents.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream =>
      _playerData.stream;

  PlaybackEventMessage _event(ProcessingStateMessage state) =>
      PlaybackEventMessage(
        processingState: state,
        updateTime: DateTime.now(),
        updatePosition: position,
        bufferedPosition: duration,
        duration: duration,
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      );

  void _cancelTimer() {
    _finishTimer?.cancel();
    _finishTimer = null;
    _moveTimer?.cancel();
    _moveTimer = null;
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    if (loadDelay > Duration.zero) {
      await Future<void>.delayed(loadDelay);
    }
    loadCount++;
    final message = request.audioSourceMessage;
    if (message is UriAudioSourceMessage) loadUris.add(message.uri);
    if (message is UriAudioSourceMessage &&
        failLoadSubstrings.any(message.uri.contains)) {
      throw PlatformException(
          code: 'load_failed', message: 'injected failure: ${message.uri}');
    }
    position = request.initialPosition ?? Duration.zero;
    _seekedSinceLoad = false;
    // Unblock AudioPlayer._load: it waits for a non-loading state.
    _playbackEvents.add(_event(ProcessingStateMessage.ready));
    return LoadResponse(duration: duration);
  }

  /// Test helper (v13.2, stale-finish race): inject a `completed`
  /// state event as if the loaded file had just ended — e.g. the
  /// previous item finishing while the next item is still loading.
  /// The controller must ignore it (its finish token does not match
  /// the in-flight load) instead of advancing the new queue.
  void emitCompleted() {
    position = duration;
    _playbackEvents.add(_event(ProcessingStateMessage.completed));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    // v13.16: injected failure — a corrupt local file hangs the
    // real player's play() until the controller's timeout fires.
    if (failPlayBox.count > 0) {
      failPlayBox.count--;
      throw TimeoutException('injected play failure (v13.16 test)');
    }
    playing = true;
    _playerData.add(PlayerDataMessage(playing: true));
    _cancelTimer();
    // Nudge past the seek point so _waitForPositionBeyond passes.
    // v13.17: with movePositionAfter set, the nudge is scheduled
    // instead of immediate — play() still returns at once, so the
    // controller waits for the movement in _waitForPositionBeyond.
    // The finish timer starts only after the nudge, so the item
    // cannot "finish" before it ever moved.
    void nudge() {
      position += const Duration(milliseconds: 250);
      _playbackEvents.add(_event(ProcessingStateMessage.ready));
      // Then finish the item with exactly ONE trigger (see class
      // doc): a position jump for a word play, a single completed
      // state otherwise.
      if (autoFinish) {
        _finishTimer = Timer(const Duration(milliseconds: 100), () {
          if (!playing) return;
          if (_seekedSinceLoad) {
            position += const Duration(seconds: 5);
            _playbackEvents.add(_event(ProcessingStateMessage.ready));
          } else {
            position = duration;
            _playbackEvents.add(_event(ProcessingStateMessage.completed));
          }
        });
      }
    }

    if (movePositionAfter > Duration.zero) {
      // The stream is buffering: report it, so just_audio's
      // position stays frozen at updatePosition (it extrapolates
      // from wall-clock only while state == ready — a buffering
      // stream must NOT look like it is moving). The nudge at
      // movePositionAfter flips the state back to ready with the
      // position advanced.
      _playbackEvents.add(_event(ProcessingStateMessage.buffering));
      _moveTimer = Timer(movePositionAfter, () {
        if (!playing) return;
        nudge();
      });
    } else {
      nudge();
    }
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    playing = false;
    _cancelTimer();
    _playerData.add(PlayerDataMessage(playing: false));
    _playbackEvents.add(_event(ProcessingStateMessage.ready));
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    _cancelTimer();
    // A seek to a NONZERO position means "play a word slice" (the
    // position-jump finish). A seek to zero is just "start from the
    // beginning" — the file then plays to its real end and finishes
    // with `completed`, exactly like the real platform: the wbw word
    // files (v13.2) are loaded then seeked to 0, and their finish
    // must arrive via `completed` so repeat/replay works for them.
    _seekedSinceLoad =
        request.position != null && request.position! > Duration.zero;
    if (request.position != null) position = request.position!;
    _playbackEvents.add(_event(ProcessingStateMessage.ready));
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async =>
      SetPitchResponse();

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
    SetSkipSilenceRequest request,
  ) async =>
      SetSkipSilenceResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async =>
      SetShuffleModeResponse();

  @override
  Future<SetAutomaticallyWaitsToMinimizeStallingResponse>
      setAutomaticallyWaitsToMinimizeStalling(
    SetAutomaticallyWaitsToMinimizeStallingRequest request,
  ) async =>
          SetAutomaticallyWaitsToMinimizeStallingResponse();

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
    SetAndroidAudioAttributesRequest request,
  ) async =>
      SetAndroidAudioAttributesResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    _cancelTimer();
    return DisposeResponse();
  }
}
