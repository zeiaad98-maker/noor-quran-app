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

class FakeAudioPlayerPlatform extends AudioPlayerPlatform {
  FakeAudioPlayerPlatform(super.id, {required this.autoFinish});

  final _playbackEvents = StreamController<PlaybackEventMessage>.broadcast();
  final _playerData = StreamController<PlayerDataMessage>.broadcast();

  Duration position = Duration.zero;
  Duration duration = const Duration(seconds: 60);
  bool playing = false;

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
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    loadCount++;
    final message = request.audioSourceMessage;
    if (message is UriAudioSourceMessage) loadUris.add(message.uri);
    position = request.initialPosition ?? Duration.zero;
    _seekedSinceLoad = false;
    // Unblock AudioPlayer._load: it waits for a non-loading state.
    _playbackEvents.add(_event(ProcessingStateMessage.ready));
    return LoadResponse(duration: duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    playing = true;
    _playerData.add(PlayerDataMessage(playing: true));
    // Nudge past the seek point so _waitForPositionBeyond passes.
    position += const Duration(milliseconds: 250);
    _playbackEvents.add(_event(ProcessingStateMessage.ready));
    // Then finish the item with exactly ONE trigger (see class
    // doc): a position jump for a word play, a single completed
    // state otherwise.
    _cancelTimer();
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
    _seekedSinceLoad = true;
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
