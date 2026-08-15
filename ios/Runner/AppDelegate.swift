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
  var snapshotView: UIView?

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    
    if let window = self.window, let rootViewController = window.rootViewController {
        // Create a snapshot to show in the App Switcher
        snapshotView = window.snapshotView(afterScreenUpdates: false)
        if let snapshot = snapshotView {
            window.addSubview(snapshot)
        }
        
        // Hide the Flutter view to prevent 0x2BAD45EC (Insecure drawing)
        rootViewController.view.isHidden = true
    }
    
    backgroundTask = application.beginBackgroundTask(withName: "BoorusamaSafetyBuffer") { [weak self] in
      self?.endBackgroundTask(application)
    }
    
    // Give Flutter 5 seconds to finish file/database operations before suspending
    DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) { [weak self] in
      self?.endBackgroundTask(application)
    }
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    super.applicationWillEnterForeground(application)
    
    if let window = self.window, let rootViewController = window.rootViewController {
        rootViewController.view.isHidden = false
        snapshotView?.removeFromSuperview()
        snapshotView = nil
    }
  }

  private func endBackgroundTask(_ application: UIApplication) {
    if backgroundTask != .invalid {
      application.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }
}
