import CoreMotion
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

    // Version check (lib/state/update_gate.dart): the version of this binary, the one the App Store compares.
    FlutterMethodChannel(name: "infyter/app_version", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "versionName" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
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

    InfyterSteps.register(with: messenger)
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

// Core Motion side of lib/services/step_source_ios.dart: availability, permission and whole local days.
enum InfyterSteps {
  private static let pedometer = CMPedometer()
  private static let maxDays = 7
  private static let askTimeout: TimeInterval = 60

  static func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "infyter/steps", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "isAvailable":
          result(CMPedometer.isStepCountingAvailable())
        case "permissionStatus":
          result(permissionStatus())
        case "requestPermission":
          requestPermission(result)
        case "readDays":
          let args = call.arguments as? [String: Any]
          let asked = args?["days"] as? Int ?? maxDays
          let from = (args?["fromMs"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
          readDays(min(max(asked, 1), maxDays), from: from, result: result)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }

  private static func permissionStatus() -> String {
    switch CMPedometer.authorizationStatus() {
    case .authorized:
      return "granted"
    case .notDetermined:
      return "notDetermined"
    case .denied, .restricted:
      return "denied"
    @unknown default:
      return "denied"
    }
  }

  // Core Motion has no request call: the first query shows the system dialog, so this waits for the status to change.
  private static func requestPermission(_ result: @escaping FlutterResult) {
    guard CMPedometer.isStepCountingAvailable(), CMPedometer.authorizationStatus() == .notDetermined else {
      result(permissionStatus())
      return
    }
    var answered = false
    func answer() {
      guard !answered else { return }
      answered = true
      result(permissionStatus())
    }
    func waitForAnswer() {
      guard !answered else { return }
      if CMPedometer.authorizationStatus() != .notDetermined {
        answer()
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { waitForAnswer() }
    }
    let now = Date()
    pedometer.queryPedometerData(from: localCalendar().startOfDay(for: now), to: now) { _, _ in
      DispatchQueue.main.async { waitForAnswer() }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + askTimeout) { answer() }
  }

  // Oldest day first, each from its midnight to the next one (now for today) and never before `from`; a day whose query fails or counts 0 steps is left out, never sent as 0.
  private static func readDays(_ count: Int, from: Date?, result: @escaping FlutterResult) {
    let calendar = localCalendar()
    let now = Date()
    var ranges: [(day: Date, start: Date, end: Date)] = []
    for back in (0..<count).reversed() {
      guard let shifted = calendar.date(byAdding: .day, value: -back, to: now) else { continue }
      let day = calendar.startOfDay(for: shifted)
      var end = now
      if back > 0 {
        guard let following = calendar.date(byAdding: .day, value: 1 - back, to: now) else { continue }
        end = calendar.startOfDay(for: following)
      }
      let start = max(day, from ?? day)
      if start < end {
        ranges.append((day: day, start: start, end: end))
      }
    }
    var days: [[String: Any]] = []
    func query(_ index: Int) {
      guard index < ranges.count else {
        result(days)
        return
      }
      let range = ranges[index]
      pedometer.queryPedometerData(from: range.start, to: range.end) { data, error in
        DispatchQueue.main.async {
          if error == nil, let steps = data?.numberOfSteps.intValue, steps > 0 {
            days.append(["day": dayKey(range.day, calendar: calendar), "steps": steps])
          }
          query(index + 1)
        }
      }
    }
    query(0)
  }

  private static func localCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.autoupdatingCurrent
    return calendar
  }

  private static func dayKey(_ date: Date, calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}
