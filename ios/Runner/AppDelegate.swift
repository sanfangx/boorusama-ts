import UIKit
import Flutter
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }

    if let controller = window?.rootViewController as? FlutterViewController {
      let fileSystemChannel = FlutterMethodChannel(name: "com.degenk.boorusama/filesystem",
                                                   binaryMessenger: controller.binaryMessenger)
      fileSystemChannel.setMethodCallHandler({
        (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
        if call.method == "excludeFromBackup" {
          guard let args = call.arguments as? [String: Any],
                let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Path is required", details: nil))
            return
          }
          var url = URL(fileURLWithPath: path)
          var resourceValues = URLResourceValues()
          resourceValues.isExcludedFromBackup = true
          do {
            try url.setResourceValues(resourceValues)
            result(true)
          } catch {
            result(FlutterError(code: "UNAVAILABLE", message: "Failed to exclude from backup", details: error.localizedDescription))
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      })
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
        GeneratedPluginRegistrant.register(with: registry)
    }

    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
  var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    
    backgroundTask = application.beginBackgroundTask(withName: "BoorusamaSafetyBuffer") { [weak self] in
      self?.endBackgroundTask(application)
    }
    
    // Give Flutter 5 seconds to finish file/database operations before suspending
    DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) { [weak self] in
      self?.endBackgroundTask(application)
    }
  }

  private func endBackgroundTask(_ application: UIApplication) {
    if backgroundTask != .invalid {
      application.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }
}
