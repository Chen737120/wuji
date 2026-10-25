// 骑行跟随控制器测试（Task 2）。算法唯一真源：
// docs/superpowers/prototypes/fancam-follow/gen_d5.dart（_load 低置信 carry / _axis 骑行状态机）。
// 合成用例约定：src 1280×720、fps 30、点列 score 全 1（除低置信用例）；
// 标准框 = gen_d5 Conf 视频1/2 的 340×604 像素（归一化 w=340/1280、h=604/720）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wuji/editing/crop_box.dart';
import 'package:wuji/editing/fancam_follow_controller.dart';
import 'package:wuji/editing/fancam_tracker.dart';

TrackPoint _pt(double frame, double x, double y, [double score = 1.0]) =>
    TrackPoint(frame / 30, x, y, score);

/// gen_d5 Conf 视频1/2 像素框 340×604 的归一化比例框。
CropBox _box340x604() =>
    CropBox(cx: 0.5, cy: 0.5, w: 340 / 1280, h: 604 / 720);

/// gen_d5 Conf 视频3 像素框 272×484 的归一化比例框。
CropBox _box272x484() =>
    CropBox(cx: 0.5, cy: 0.5, w: 272 / 1280, h: 484 / 720);

void main() {
  group('fancam_follow_controller（骑行跟随，gen_d5 逐行移植）', () {
    test('用例1: 静止目标——HOLD 全程 centers 等于初始 clamp 位置', () {
      final pts = [for (var i = 0; i < 30; i++) _pt(i.toDouble(), 640, 360)];
      final s = FollowSession(
          points: pts, box: _box340x604(), srcW: 1280, srcH: 720);
      s.recompute(fps: 30, duration: const Duration(seconds: 1));
      expect(s.centers.length, 31, reason: '帧0 ＋ duration×fps=30 帧');
      for (var i = 0; i < s.centers.length; i++) {
        expect(s.centers[i].t, closeTo(i / 30, 1e-9), reason: '帧$i 时间戳');
        expect(s.centers[i].x, closeTo(640, 1e-9), reason: '帧$i x（HOLD 不动）');
        expect(s.centers[i].y, closeTo(360, 1e-9), reason: '帧$i y（HOLD 不动）');
      }
    });

    test('用例2: 匀速目标 1px/帧——|人物−框中心| ≤ z·box＋2px', () {
      final pts = [
        for (var i = 0; i < 90; i++) _pt(i.toDouble(), 640.0 + i, 360),
      ];
      final s = FollowSession(
          points: pts, box: _box340x604(), srcW: 1280, srcH: 720);
      s.recompute(fps: 30, duration: const Duration(seconds: 3));
      // 骑行必须被触发（否则框不动、测试退化）
      expect(s.statsX.moves, greaterThanOrEqualTo(1), reason: '横轴应触发骑行');
      // 偏移断言（独立于实现 stats 重算）：off = 人物 − 框中心
      // （centers=帧0＋90 帧=91 项；pts 只有 0..89 帧，最后一帧的采样沿用 pts[89]）
      final zXpx = 0.12 * 340, zYpx = 0.05 * 604;
      for (var i = 0; i < pts.length; i++) {
        expect((pts[i].x - s.centers[i].x).abs(), lessThanOrEqualTo(zXpx + 2),
            reason: '帧$i 横向偏移 ≤ 死区+2px');
        expect((pts[i].y - s.centers[i].y).abs(), lessThanOrEqualTo(zYpx + 2),
            reason: '帧$i 纵向偏移 ≤ 死区+2px');
      }
      expect(s.statsX.outFrames, 0, reason: '中心出框 0 帧');
    });

    test('用例3: 低置信 carry——score<0.6 帧沿用上一有效位置（Review Focus #1）', () {
      // 前 10 帧在 A(640,360)；5 帧 score=0.5 误跳到远端 B(940,360)；随后在 B 恢复
      final pts = <TrackPoint>[
        for (var i = 0; i < 10; i++) _pt(i.toDouble(), 640, 360),
        for (var i = 10; i < 15; i++) _pt(i.toDouble(), 940, 360, 0.5),
        for (var i = 15; i < 45; i++) _pt(i.toDouble(), 940, 360),
      ];
      final s = FollowSession(
          points: pts, box: _box340x604(), srcW: 1280, srcH: 720);
      s.recompute(fps: 30, duration: const Duration(milliseconds: 1500));
      // 低置信段（帧 10..14）：输入被 carry 在 A，控制器不得看到 B（否则中心被快层拉走）
      for (var i = 10; i <= 14; i++) {
        expect(s.centers[i].x, closeTo(640, 1e-9), reason: '帧$i x 应 carry A');
        expect(s.centers[i].y, closeTo(360, 1e-9), reason: '帧$i y 应 carry A');
      }
      // carry 前最后一帧（帧9）与低置信段首帧（帧10）一致
      expect(s.centers[10].x, s.centers[9].x);
      // 恢复高置信后控制器重新看到 B（中心被拉向 B）
      expect(s.centers[15].x, greaterThan(700), reason: '帧15 起 carry 结束');
      // 低置信 5 帧 = 0.167s ≤ 1s → 不提示
      expect(s.lossHint(), isNull);
    });

    test('用例3b: lossHint——最长低置信连续段 >1s 返回提示文案', () {
      // 30 帧连续低置信 = 1.0s（不 >1）→ null；35 帧 = 1.167s → 提示
      List<TrackPoint> lowRun(int n) => <TrackPoint>[
            _pt(0, 640, 360),
            for (var i = 1; i <= n; i++) _pt(i.toDouble(), 700, 380, 0.4),
          ];
      final s30 = FollowSession(
          points: lowRun(30), box: _box340x604(), srcW: 1280, srcH: 720);
      expect(s30.lossHint(), isNull, reason: '恰 1.0s 不触发');
      final s35 = FollowSession(
          points: lowRun(35), box: _box340x604(), srcW: 1280, srcH: 720);
      expect(s35.lossHint(), '目标丢失，点击画面重新锁定');
    });

    test('用例4: 锚点经过——锚点时刻差<1px，±1s 外回基线（Review Focus #3）', () {
      final pts = [for (var i = 0; i < 90; i++) _pt(i.toDouble(), 640, 360)];
      final s = FollowSession(
          points: pts, box: _box340x604(), srcW: 1280, srcH: 720);
      s.recompute(fps: 30, duration: const Duration(seconds: 3));
      // 基线全 (640,360)。模拟用户在 t=1s 把框拖到 (768,360)（归一化 0.6/0.5）
      s.insertAnchor(const Duration(seconds: 1), cx: 0.6, cy: 0.5);
      expect(s.anchors.length, 1);
      expect(s.anchors.single.t, const Duration(seconds: 1));
      // 锚点混合同步更新 centers（ruling：无需再显式 recompute）
      expect((s.centers[30].x - 768).abs(), lessThan(1.0),
          reason: 't=1.0s 权值=1 必须经过锚点');
      expect((s.centers[30].y - 360).abs(), lessThan(1.0));
      // 中点过渡：t=1.5s 权重 0.5 → 640＋0.5×128 = 704
      expect(s.centers[45].x, closeTo(704, 1e-6), reason: '余弦窗中点权重 0.5');
      // ±1s 外与基线重合：帧60 恰在窗缘（权重 0），帧80 窗外
      expect(s.centers[60].x, closeTo(640, 1e-9), reason: 't=2.0s 窗缘权重 0');
      expect(s.centers[60].y, closeTo(360, 1e-9));
      expect(s.centers[80].x, closeTo(640, 1e-9), reason: 't=2.67s 窗外');
      // 默认签名：insertAnchor 取当前轨迹中心（delta=0，轨迹不变）
      s.insertAnchor(const Duration(seconds: 2));
      expect(s.anchors.length, 2);
      expect(s.centers[60].x, closeTo(640, 1e-9), reason: 'delta=0 无影响');
      // removeAnchor 删最近锚点（t=99s 最近的是 t=2s 锚），混合同步回基线
      s.removeAnchor(const Duration(seconds: 99));
      expect(s.anchors.length, 1);
      expect(s.anchors.single.t, const Duration(seconds: 1));
      expect(s.centers[0].x, closeTo(640, 1e-9));
      s.removeAnchor(const Duration(seconds: 1));
      expect(s.anchors, isEmpty);
      expect(s.centers[30].x, closeTo(640, 1e-9), reason: '删除后恢复基线');
    });

    test('用例5: buildSendCmd——首帧行格式/偶数化/行数（Review Focus #2）', () {
      final pts = [for (var i = 0; i < 30; i++) _pt(i.toDouble(), 640, 360)];
      final s = FollowSession(
          points: pts, box: _box340x604(), srcW: 1280, srcH: 720);
      s.recompute(fps: 30, duration: const Duration(seconds: 1));
      final cmd = s.buildSendCmd();
      expect(cmd.endsWith('\n'), isTrue, reason: '每行以换行结尾（文件直写语义）');
      final lines = cmd.split('\n')..removeLast();
      expect(lines.length, 62, reason: '2×帧数（31 帧）');
      // 首帧行：x=中心−半宽取整再偶数化（640−170=470 已偶；360−302=58 已偶）。
      // 格式必须是 sendcmd 三段式 "t crop x V;"（target+command+arg）——
      // ffmpeg 9 实测两段式 "crop.x V" 被解析为 target:"crop.x" command:"V"，
      // 无滤镜匹配、静默失效（Task 3 PC 冒烟发现，证据见 task-3-report.md）
      expect(lines[0], '0.0000 crop x ${(640 - 170).round() & ~1};');
      expect(lines[1], '0.0000 crop y ${(360 - 302).round() & ~1};');
      expect(lines[0], '0.0000 crop x 470;');
      expect(lines[1], '0.0000 crop y 58;');
      // 全部行：x/y 偶数、t 升序、crop x/crop y 交替
      var prevT = -1.0;
      for (var i = 0; i < lines.length; i++) {
        final parts = lines[i].split(' ');
        expect(parts.length, 4, reason: '行格式 "t crop x|y V;"：${lines[i]}');
        final t = double.parse(parts[0]);
        expect(t, greaterThanOrEqualTo(prevT), reason: 't 升序');
        prevT = t;
        final v = int.parse(parts[3].split(';')[0]);
        expect(v.isEven, isTrue, reason: '偶数化：${lines[i]}');
        expect(parts[2], i.isEven ? 'x' : 'y');
      }
    });

    test('用例7: followCropSize——floor/偶数化/clamp ≥16 ≤源最大偶数', () {
      // 归一化回乘精度已验证（340/604/272/484 均 floor 回目标值）
      expect(followCropSize(_box340x604(), 1280, 720), (340, 604));
      expect(followCropSize(_box272x484(), 1280, 720), (272, 484));
      // 奇数像素（341×720）→ 偶数化
      expect(
        followCropSize(
            CropBox(cx: .5, cy: .5, w: 341 / 1280, h: 1.0), 1280, 720),
        (340, 720),
      );
      // 过小 → ≥16
      expect(
        followCropSize(
            CropBox(cx: .5, cy: .5, w: 0.005, h: 0.005), 1280, 720),
        (16, 16),
      );
      // 超源 → 源最大偶数
      expect(
        followCropSize(CropBox(cx: .5, cy: .5, w: 1.5, h: 1.5), 1280, 720),
        (1280, 720),
      );
      // 奇数源：上限取源最大偶数（720→719 时 maxEven=718）
      expect(
        followCropSize(CropBox(cx: .5, cy: .5, w: 1.5, h: 1.0), 1280, 719),
        (1280, 718),
      );
    });

    test('用例8: withBox——换框重建保留锚点并重混合，原会话不受影响（Task 4 ruling 3）', () {
      final pts = [for (var i = 0; i < 60; i++) _pt(i.toDouble(), 640, 360)];
      final origBox = _box340x604();
      final s = FollowSession(
          points: pts, box: origBox, srcW: 1280, srcH: 720);
      s.recompute(fps: 30, duration: const Duration(seconds: 2));
      s.insertAnchor(const Duration(seconds: 1), cx: 0.6, cy: 0.5);
      final newBox = _box272x484();
      final s2 = s.withBox(newBox, fps: 30, duration: const Duration(seconds: 2));
      // 框已替换；锚点原样保留（同刻同位置）
      expect(s2.box, same(newBox), reason: '会话框替换为传入框');
      expect(s2.anchors.length, 1, reason: '锚点随重建保留');
      expect(s2.anchors.single.t, const Duration(seconds: 1));
      expect(s2.anchors.single.cx, closeTo(0.6, 1e-9));
      expect(s2.anchors.single.cy, closeTo(0.5, 1e-9));
      // 轨迹帧数不变；静止目标下新会话锚点时刻仍精确经过（0.6×1280=768）
      expect(s2.centers.length, s.centers.length, reason: '轨迹帧数与原会话一致');
      expect((s2.centers[30].x - 768).abs(), lessThan(1.0),
          reason: '重建后 t=1s 仍经过锚点');
      expect((s2.centers[30].y - 360).abs(), lessThan(1.0));
      // 原会话完全不变（页面侧以新会话替换旧会话，旧引用不得被改写）
      expect(s.box, same(origBox));
      expect(s.anchors.length, 1);
      expect((s.centers[30].x - 768).abs(), lessThan(1.0), reason: '原轨迹不变');
      // 无锚点会话同样可换框（自动模式改比例/还原的常见路径）
      final s3 = FollowSession(
          points: pts, box: _box340x604(), srcW: 1280, srcH: 720);
      s3.recompute(fps: 30, duration: const Duration(seconds: 2));
      final s4 = s3.withBox(_box272x484(),
          fps: 30, duration: const Duration(seconds: 2));
      expect(s4.anchors, isEmpty);
      expect(s4.centers.length, 61);
    });

    test('用例9: followBoxAt——最后 t≤trackT 轨迹点→归一化框；空轨迹回 session.box', () {
      final pts = [for (var i = 0; i < 60; i++) _pt(i.toDouble(), 640, 360)];
      final s = FollowSession(
          points: pts, box: _box340x604(), srcW: 1280, srcH: 720);
      s.recompute(fps: 30, duration: const Duration(seconds: 2));
      s.insertAnchor(const Duration(seconds: 1), cx: 0.6, cy: 0.5);
      // t=0 在锚点窗缘（权重 0）→ 基线中心 640,360 → 归一化 (0.5, 0.5)
      final b0 = followBoxAt(s, Duration.zero);
      expect(b0.cx, closeTo(640 / 1280, 1e-9));
      expect(b0.cy, closeTo(0.5, 1e-9));
      expect(b0.w, s.box.w, reason: '尺寸恒为 session.box（跟随框尺寸恒定语义）');
      expect(b0.h, s.box.h);
      // 锚点时刻：中心=锚点像素 768 → 归一化 0.6
      final bAnchor = followBoxAt(s, const Duration(milliseconds: 1000));
      expect(bAnchor.cx, closeTo(0.6, 1e-6), reason: '锚点时刻取锚点中心');
      expect(bAnchor.cy, closeTo(0.5, 1e-9));
      // 窗外（t=2s）回基线；t 超尾取末点；t 为负取首点
      expect(followBoxAt(s, const Duration(seconds: 2)).cx, closeTo(0.5, 1e-9));
      expect(followBoxAt(s, const Duration(hours: 1)).cx, closeTo(0.5, 1e-9),
          reason: 't 超尾 → 末点');
      expect(followBoxAt(s, const Duration(seconds: -5)).cx, closeTo(0.5, 1e-9),
          reason: 't 为负 → 首点');
      // 空轨迹（未 recompute 的会话）：回退 session.box，不抛
      final empty = FollowSession(
          points: const [], box: _box340x604(), srcW: 1280, srcH: 720);
      final be = followBoxAt(empty, Duration.zero);
      expect(be.cx, empty.box.cx);
      expect(be.cy, empty.box.cy);
      expect(be.w, empty.box.w);
      expect(be.h, empty.box.h);
    });

    test('用例6: 三素材指标回归——maxE ≤ z·box+20、中心出框 0 帧（缺失即跳过）', () {
      const confs = [
        // (名, CSV, boxW, boxH, 时长)——gen_d5 Conf 口径：340×604/340×604/272×484，
        // 时长 32.45/36.0/26.8333s（原型"跟踪可靠段"裁剪）
        ('v1', 'testdata/fancam-follow/track_v1.csv', 340, 604,
            Duration(milliseconds: 32450)),
        ('v3', 'testdata/fancam-follow/track_v3.csv', 340, 604,
            Duration(seconds: 36)),
        ('v4', 'testdata/fancam-follow/track_v4.csv', 272, 484,
            Duration(milliseconds: 26833)),
      ];
      for (final c in confs) {
        final f = File(c.$2);
        if (!f.existsSync()) {
          // ignore: avoid_print
          print('skip ${c.$1}: 缺 ${c.$2}（CI 无 testdata；PC 上 '
              'WUJI_GEN_FIXTURE=1 flutter test '
              'test/editing/fancam_follow_fixture_gen_test.dart 生成）');
          continue;
        }
        final pts = <TrackPoint>[];
        for (final line in f.readAsLinesSync()) {
          final p = line.split(',');
          if (p.length < 4) continue;
          pts.add(TrackPoint(double.parse(p[0]), double.parse(p[1]),
              double.parse(p[2]), double.parse(p[3])));
        }
        final s = FollowSession(
          points: pts,
          box: CropBox(cx: 0.5, cy: 0.5, w: c.$3 / 1280, h: c.$4 / 720),
          srcW: 1280,
          srcH: 720,
        );
        s.recompute(fps: 30, duration: c.$5);
        final limitX = 0.12 * c.$3 + 20, limitY = 0.05 * c.$4 + 20;
        // ignore: avoid_print
        print('${c.$1}: maxE x=${s.statsX.maxE.toStringAsFixed(1)}'
            '/y=${s.statsY.maxE.toStringAsFixed(1)}px（限 $limitX/$limitY）'
            ' 出框 x=${s.statsX.outFrames}/y=${s.statsY.outFrames}'
            ' 触发 x=${s.statsX.moves}/y=${s.statsY.moves}'
            ' 碰缘 x=${s.statsX.nearEdge}/y=${s.statsY.nearEdge}'
            ' 回中受限 x=${s.statsX.emFrames}/y=${s.statsY.emFrames}'
            ' 帧数=${s.centers.length}');
        expect(s.statsX.maxE, lessThanOrEqualTo(limitX),
            reason: '${c.$1} 横轴 maxE ≤ z·box+20');
        expect(s.statsY.maxE, lessThanOrEqualTo(limitY),
            reason: '${c.$1} 纵轴 maxE ≤ z·box+20');
        expect(s.statsX.outFrames, 0, reason: '${c.$1} 横轴中心出框 0 帧');
        expect(s.statsY.outFrames, 0, reason: '${c.$1} 纵轴中心出框 0 帧');
      }
    });
  });
}
