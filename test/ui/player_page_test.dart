import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:wuji/ui/player_page.dart';

/// 轻量假平台：只实现 PlayerPage 走到的通路（构造→initialize→play 轮询位置）。
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  static const int _playerId = 7;
  Duration position = Duration.zero;
  bool? looping;
  bool playing = false;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      _playerId;

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      Stream<VideoEvent>.fromIterable([
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 18),
          size: const Size(320, 240),
        ),
      ]);

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
          int playerId, bool preventsDisplaySleepDuringVideoPlayback) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async =>
      this.looping = looping;

  @override
  Future<void> play(int playerId) async => playing = true;

  @override
  Future<void> pause(int playerId) async => playing = false;

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      this.position = position;

  @override
  Future<Duration> getPosition(int playerId) async => position;

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Widget buildView(int playerId) => const SizedBox.expand();

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => buildView(0);
}

void main() {
  late _FakeVideoPlayerPlatform fake;

  setUp(() {
    fake = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fake;
  });

  Future<void> pumpPlayer(WidgetTester tester, {bool loop = false}) async {
    await tester.pumpWidget(MaterialApp(
        home: PlayerPage(fileName: '/fake/x.mp4', loop: loop)));
    await tester.pump(); // initialize 的 event stream 投递
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('进度条右侧时间随播放位置刷新（用户 2026-10-31 缺陷回归）',
      (tester) async {
    await pumpPlayer(tester);
    expect(find.text('00:00 / 00:18'), findsOneWidget);

    // 平台位置推进后，只靠 controller 值变化（不点暂停/不 setState）也应刷新
    fake.position = const Duration(seconds: 7);
    await tester.pump(const Duration(milliseconds: 150)); // 100ms 位置轮询
    expect(find.text('00:07 / 00:18'), findsOneWidget);
    expect(find.text('00:00 / 00:18'), findsNothing);

    fake.position = const Duration(seconds: 12);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('00:12 / 00:18'), findsOneWidget);
  });

  testWidgets('loop 开关透传到平台：记录流入口 true、其余默认 false',
      (tester) async {
    await pumpPlayer(tester, loop: true);
    expect(fake.looping, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    final fake2 = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = fake2;
    await pumpPlayer(tester);
    // controller 初始化会下发一次 setLooping(false)；关键是与 loop:true 区分
    expect(fake2.looping, isFalse);
  });
}
