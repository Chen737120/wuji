import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 与 Android MainActivity 的 wuji/native 通道同协议：
    // setKeepScreenOn → isIdleTimerDisabled（导入/导出期间屏幕常亮）；
    // excludeFromBackup → NSURLIsExcludedFromBackupKey（存档/数据库不进 iCloud 备份）；
    // scanMedia 无需实现（iOS 相册感知由系统完成），回复 nil 保持协议兼容。
    let channel = FlutterMethodChannel(
      name: "wuji/native",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setKeepScreenOn":
        let args = call.arguments as? [String: Any]
        UIApplication.shared.isIdleTimerDisabled = (args?["on"] as? Bool) ?? false
        result(nil)
      case "excludeFromBackup":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "badArgs", message: "path required", details: nil))
          return
        }
        let url = URL(fileURLWithPath: path)
        try? (url as NSURL).setResourceValue(true, forKey: .isExcludedFromBackupKey)
        result(nil)
      case "scanMedia":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
