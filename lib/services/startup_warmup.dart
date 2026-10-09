import 'dart:io';

import 'package:flutter/widgets.dart';

import '../data/db.dart' show ClassRecord, ClassRecordRowX, MediaAsset;
import 'abs_path_cache.dart';
import 'archive_fs.dart';

/// 启动预热（2026-10-08 需求 #5）：数据多时冷启动首屏能看到封面/图片
/// 从占位一格一格加载出来。参考舞动时光「启动加载页」的做法：启动页
/// 期间把首屏要用的封面路径解析好、按列表实际解码宽度预解码进 Flutter
/// 图片缓存，首页首帧即为成图；没赶上的部分由软占位色兜底。
class StartupWarmup {
  StartupWarmup._();

  /// 用户最近一次滚动首页/统计列表的时间（页面在 ScrollUpdateNotification
  /// 里上报）。v1.5.20 教训：全量预热与快速滚动同时跑会打满 UI 线程
  /// （SAF 拷贝 + 解码竞争）→ 卡顿甚至 ANR 被杀；预热必须给交互让路。
  static DateTime _lastUserScroll = DateTime.fromMillisecondsSinceEpoch(0);

  /// 列表滚动时调用（高频、零开销：只写一个时间戳）。
  static void noteUserScroll() => _lastUserScroll = DateTime.now();

  /// 用户在 1.8 秒内滚动过 → 视为正在浏览，暂停预热。
  static bool get _userRecentlyScrolled =>
      DateTime.now().difference(_lastUserScroll) <
      const Duration(milliseconds: 1800);

  /// 等到用户停止交互（最多每 250ms 探一次）；页面关闭即返回。
  static Future<void> _awaitUiCalm(BuildContext context) async {
    while (context.mounted && _userRecentlyScrolled) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// 预热首屏：最近 [recordLimit] 条记录的媒体网格图（cacheWidth 500，
  /// 与首页卡片网格一致）＋ 当前月日历封面（cacheWidth 300，与日历格子
  /// 一致）。返回预热成功的条数（诊断用）。
  static Future<int> warmFirstScreen(
    BuildContext context, {
    required List<ClassRecord> records,
    required Map<String, List<MediaAsset>> mediaByClass,
    required MediaPathResolver? resolver,
    int recordLimit = 8,
  }) async {
    final gridRels = <String>{};
    for (final r in records.take(recordLimit)) {
      for (final m in (mediaByClass[r.id] ?? const <MediaAsset>[]).take(6)) {
        final rel = m.thumbName ?? (m.type == 'image' ? m.fileName : null);
        if (rel != null) gridRels.add(rel);
      }
    }
    // 当前月日历封面：同一天取第一条记录的第一个视频封面（与首页一致）
    final now = DateTime.now();
    final coverRels = <String>{};
    final seenDays = <int>{};
    for (final r in records) {
      final d = r.dateAsDateTime;
      if (d.year != now.year || d.month != now.month) continue;
      if (!seenDays.add(d.day)) continue;
      final media = mediaByClass[r.id];
      if (media == null || media.isEmpty) continue;
      MediaAsset? pick;
      for (final m in media) {
        if (m.type == 'video' && m.thumbName != null) {
          pick = m;
          break;
        }
      }
      pick ??= media.first;
      final rel =
          pick.thumbName ?? (pick.type == 'image' ? pick.fileName : null);
      if (rel != null) coverRels.add(rel);
    }

    // 1) 绝对路径解析（SAF 首次=复制到缓存目录，是最慢的一步，先统一做；
    //    与页面 FutureBuilder 共享 AbsPathCache 去重，不会重复拷贝）
    final gridPaths = <String, String?>{
      for (final rel in gridRels) rel: await AbsPathCache.resolve(resolver, rel),
    };
    final coverPaths = <String, String?>{
      for (final rel in coverRels)
        rel: gridPaths[rel] ?? await AbsPathCache.resolve(resolver, rel),
    };
    if (!context.mounted) return 0;

    // 2) 预解码进图片缓存：provider 构造与 Image.file(cacheWidth:..) 一致
    //    → 首页首帧直接命中缓存，无解码闪现
    var warmed = 0;
    for (final e in gridPaths.entries) {
      if (!context.mounted) return warmed;
      if (await _precache(context, e.value, 500)) warmed++;
    }
    for (final e in coverPaths.entries) {
      if (!context.mounted) return warmed;
      if (await _precache(context, e.value, 300)) warmed++;
    }
    return warmed;
  }

  /// 全量预热（2026-10-09 需求 #4）：开屏 3 秒只够首屏（warmFirstScreen），
  /// 结束后在后台把**全部**记录的网格图（500 宽）与所有有课日期的日历
  /// 封面（300 宽）逐张预解码进图片缓存——此后滑到任意过往记录、切到
  /// 任意历史月份都是即时成图，不再看到逐格加载。逐张之间让出事件循环，
  /// 不拖累前台交互；页面关闭（context unmount）即中止。
  static Future<int> warmAll(
    BuildContext context, {
    required List<ClassRecord> records,
    required Map<String, List<MediaAsset>> mediaByClass,
    required MediaPathResolver? resolver,
    int mediaPerRecord = 6,
  }) async {
    // 全部记录的网格图（与首页卡片一致：每课前 6 个）
    final gridRels = <String>{};
    for (final r in records) {
      for (final m in (mediaByClass[r.id] ?? const <MediaAsset>[]).take(mediaPerRecord)) {
        final rel = m.thumbName ?? (m.type == 'image' ? m.fileName : null);
        if (rel != null) gridRels.add(rel);
      }
    }
    // 所有有课日期的日历封面（与首页 _coversIn 一致：同天取第一条记录、
    // 优先视频封面）
    final coverRels = <String>{};
    final seenDays = <String>{};
    for (final r in records) {
      final d = r.dateAsDateTime;
      if (!seenDays.add('${d.year}-${d.month}-${d.day}')) continue;
      final media = mediaByClass[r.id];
      if (media == null || media.isEmpty) continue;
      MediaAsset? pick;
      for (final m in media) {
        if (m.type == 'video' && m.thumbName != null) {
          pick = m;
          break;
        }
      }
      pick ??= media.first;
      final rel =
          pick.thumbName ?? (pick.type == 'image' ? pick.fileName : null);
      if (rel != null) coverRels.add(rel);
    }

    // 1) 绝对路径解析统一先做（SAF 首次=复制，最慢的一步；与页面共享
    //    AbsPathCache 去重）。paced=true：分块拷贝走后台线程并逐块让出
    //    UI 线程；每张之间先等用户停止滚动，滚动期间一张都不碰。
    final gridPaths = <String, String?>{};
    for (final rel in gridRels) {
      if (!context.mounted) return 0;
      await _awaitUiCalm(context);
      if (!context.mounted) return 0;
      gridPaths[rel] = await AbsPathCache.resolve(resolver, rel, paced: true);
    }
    final coverPaths = <String, String?>{};
    for (final rel in coverRels) {
      if (gridPaths.containsKey(rel)) {
        coverPaths[rel] = gridPaths[rel];
        continue;
      }
      if (!context.mounted) return 0;
      await _awaitUiCalm(context);
      if (!context.mounted) return 0;
      coverPaths[rel] = await AbsPathCache.resolve(resolver, rel, paced: true);
    }

    // 2) 预解码，每张之间让出事件循环并给交互让路
    var warmed = 0;
    for (final e in gridPaths.entries) {
      if (!context.mounted) return warmed;
      await _awaitUiCalm(context);
      if (!context.mounted) return warmed;
      if (await _precache(context, e.value, 500)) warmed++;
      await Future<void>.delayed(Duration.zero);
    }
    for (final e in coverPaths.entries) {
      if (!context.mounted) return warmed;
      await _awaitUiCalm(context);
      if (!context.mounted) return warmed;
      if (await _precache(context, e.value, 300)) warmed++;
      await Future<void>.delayed(Duration.zero);
    }
    return warmed;
  }

  static Future<bool> _precache(
      BuildContext context, String? path, int width) async {
    if (path == null) return false;
    try {
      final f = File(path);
      if (!f.existsSync()) return false;
      await precacheImage(
        ResizeImage(FileImage(f), width: width, allowUpscaling: false),
        context,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
