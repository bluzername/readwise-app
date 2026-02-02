import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    private let appGroupId = "group.live.bluzername.readzero.app"
    private let pendingUrlsKey = "pendingUrls"
    // Use lazy var so handler is only created when first accessed (not at app launch)
    private lazy var authExtractionHandler = AuthExtractionHandler()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        let controller = window?.rootViewController as! FlutterViewController

        // Set up method channel for App Group communication
        let shareChannel = FlutterMethodChannel(name: "com.readzero.app/share", binaryMessenger: controller.binaryMessenger)

        // Set up method channel for authenticated content extraction
        let extractionChannel = FlutterMethodChannel(name: "com.readzero.app/auth_extraction", binaryMessenger: controller.binaryMessenger)
        extractionChannel.setMethodCallHandler { [weak self] (call, result) in
            self?.authExtractionHandler.handleMethodCall(call, result: result)
        }

        let channel = shareChannel

        channel.setMethodCallHandler { [weak self] (call, result) in
            guard let self = self else { return }

            switch call.method {
            case "getPendingUrls":
                let urls = self.getPendingUrls()
                result(urls)
            case "clearPendingUrls":
                self.clearPendingUrls()
                result(nil)
            case "removeProcessedUrls":
                // Remove only specific URLs that were successfully processed
                if let args = call.arguments as? [String: Any],
                   let urlsToRemove = args["urls"] as? [String] {
                    self.removeProcessedUrls(urlsToRemove)
                    result(nil)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: "Expected urls array", details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
    }

    private func getPendingUrls() -> [String] {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
            print("[ReadZero] ERROR: Failed to access App Group '\(appGroupId)' - check entitlements")
            return []
        }
        let urls = userDefaults.stringArray(forKey: pendingUrlsKey) ?? []
        print("[ReadZero] Retrieved \(urls.count) pending URLs from App Group")
        for (index, url) in urls.enumerated() {
            print("[ReadZero] URL[\(index)]: \(url)")
        }
        return urls
    }

    private func clearPendingUrls() {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
            print("[ReadZero] ERROR: Failed to access App Group '\(appGroupId)' for clearing")
            return
        }
        userDefaults.removeObject(forKey: pendingUrlsKey)
        print("[ReadZero] Cleared all pending URLs")
    }

    private func removeProcessedUrls(_ urlsToRemove: [String]) {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
            print("[ReadZero] ERROR: Failed to access App Group '\(appGroupId)' for removal")
            return
        }

        var pendingUrls = userDefaults.stringArray(forKey: pendingUrlsKey) ?? []
        let originalCount = pendingUrls.count

        // Remove only the specified URLs (preserving order and handling duplicates correctly)
        for urlToRemove in urlsToRemove {
            if let index = pendingUrls.firstIndex(of: urlToRemove) {
                pendingUrls.remove(at: index)
            }
        }

        if pendingUrls.isEmpty {
            userDefaults.removeObject(forKey: pendingUrlsKey)
        } else {
            userDefaults.set(pendingUrls, forKey: pendingUrlsKey)
        }

        print("[ReadZero] Removed \(originalCount - pendingUrls.count) URLs, \(pendingUrls.count) remaining")
    }
}
