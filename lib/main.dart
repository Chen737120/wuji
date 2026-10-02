import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme.dart';
import 'ui/home_shell.dart';

void main() {
  runApp(const AppRoot());
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});
  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final _theme = ThemeController();

  @override
  void initState() {
    super.initState();
    _theme.load();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _theme,
      child: Consumer<ThemeController>(
        builder: (_, t, __) => MaterialApp(
          title: '舞记',
          theme: AppTheme.light(t.accentPreset),
          home: HomeShell(
            pages: const [Placeholder(), Placeholder()],
            onFabPressed: () {}, // T8 接表单
          ),
        ),
      ),
    );
  }
}
