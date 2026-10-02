/// sqlite3 3.x loads its native library through Dart build hooks (native
/// assets), so no manual dll override is needed on the host. Kept as a no-op
/// so tests keep calling it at setUpAll.
void configSqliteForWindowsTest() {}
