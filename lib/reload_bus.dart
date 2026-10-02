import 'package:flutter/foundation.dart';

/// 数据变更广播：新增/编辑/删除后让常驻页面（统计/记录）刷新。
class ReloadBus extends ChangeNotifier {
  ReloadBus._();
  static final ReloadBus instance = ReloadBus._();

  void bump() => notifyListeners();
}
