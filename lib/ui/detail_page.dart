import 'package:flutter/material.dart';
import '../theme.dart';

/// 课堂详情页骨架（T10 按 §3.5 完整实现）。
class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.classId});

  final String classId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const Center(
        child: Text('详情页',
            style: TextStyle(fontSize: 13, color: AppColors.secondary)),
      ),
    );
  }
}
