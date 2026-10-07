import 'package:flutter/material.dart';
import '../../theme.dart';

/// 剪辑落地页（规格 §3）：两张入口卡＋页脚说明。
class EditHubPage extends StatelessWidget {
  const EditHubPage({
    super.key,
    this.onFancam,
    this.onCompare,
  });

  final VoidCallback? onFancam;
  final VoidCallback? onCompare;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 4, 0, 12),
              child: Text('剪辑',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3)),
            ),
            _EntryCard(
              icon: Icons.center_focus_strong,
              title: '舞蹈直拍',
              subtitle: '在课堂视频上圈选一块区域，裁出竖版直拍。\n框可以跟随动作打关键帧，导出平滑跟框。',
              onTap: onFancam,
            ),
            const SizedBox(height: 16),
            _EntryCard(
              icon: Icons.compare,
              title: '同屏对比',
              subtitle: '老师视频和你的视频左右并排。\n手动对齐时间与画面，导出对比视频。',
              onTap: onCompare,
            ),
            const SizedBox(height: 20),
            Center(
              child: Text('生成的视频保存在相册，原始课堂记录不受影响',
                  style: TextStyle(fontSize: 10, color: AppColors.faint)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          // 2026-10-07 用户需求 #9：卡片调大，减少页面下部空旷感
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.6,
                            color: AppColors.secondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 22, color: Color(0xFFC9C9C5)),
            ],
          ),
        ),
      ),
    );
  }
}
