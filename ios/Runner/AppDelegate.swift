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
