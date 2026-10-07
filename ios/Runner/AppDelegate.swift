import Flutter
import Photos
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "InfyterChannels") {
      InfyterChannels.register(with: registrar.messenger())
    }
  }
}

// iOS side of the channels that MainActivity.kt implements on Android.
enum InfyterChannels {
  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "infyter/gallery", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "savePng" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let args = call.arguments as? [String: Any]
        guard let bytes = args?["bytes"] as? FlutterStandardTypedData else {
          result(FlutterError(code: "no-bytes", message: "missing image", details: nil))
          return
        }
        savePng(bytes.data, name: args?["name"] as? String ?? "infyter.png", result: result)
      }

    FlutterMethodChannel(name: "infyter/screen", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "keepOn":
          let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
          UIApplication.shared.isIdleTimerDisabled = on
          result(nil)
        case "dim":
          // Only the Wear OS shell dims the display.
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }

  private static func savePng(_ data: Data, name: String, result: @escaping FlutterResult) {
    let write: (PHAuthorizationStatus) -> Void = { status in
      guard status == .authorized else {
        DispatchQueue.main.async { result(false) }
        return
      }
      PHPhotoLibrary.shared().performChanges({
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = name
        PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: options)
      }) { success, _ in
        DispatchQueue.main.async { result(success) }
      }
    }
    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: write)
    } else {
      PHPhotoLibrary.requestAuthorization(write)
    }
  }
}
