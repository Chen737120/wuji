import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

/// Loads the sqlite3.dll vendored under test/ so host tests can run
/// NativeDatabase without a system-wide sqlite installation.
void configSqliteForWindowsTest() {
  final dll = File('test/sqlite3.dll').absolute.path;
  open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(dll));
}
