import UIKit
import Flutter
import LocalAuthentication

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "smart_house/biometrics",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        let context = LAContext()
        var authError: NSError?
        let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
        if call.method == "isAvailable" {
          result(context.canEvaluatePolicy(policy, error: &authError))
          return
        }
        if call.method == "authenticate" {
          guard context.canEvaluatePolicy(policy, error: &authError) else {
            result(false)
            return
          }
          let arguments = call.arguments as? [String: Any]
          let reason = arguments?["reason"] as? String
            ?? "Подтвердите вход в Smart House"
          context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
            DispatchQueue.main.async { result(success) }
          }
          return
        }
        result(FlutterMethodNotImplemented)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
