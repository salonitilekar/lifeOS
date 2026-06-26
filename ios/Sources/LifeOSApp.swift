import SwiftUI
import WebKit
import UserNotifications

@main
struct LifeOSApp: App {
    init() {
        TimerNotification.requestPermission()
    }

    var body: some Scene {
        WindowGroup {
            WebView()
                .ignoresSafeArea()
                .preferredColorScheme(.dark)
        }
    }
}

private enum TimerNotification {
    static let id = "lifeos.pomodoro.done"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func schedule(seconds: TimeInterval, label: String) {
        cancel()
        guard seconds > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Pomodoro done"
        content.body = label.isEmpty
            ? "Lock-in complete — take a break."
            : "\(label) — 25 minutes up."
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, seconds),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }
}

struct WebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .default()
        config.userContentController.add(context.coordinator, name: "haptic")
        config.userContentController.add(context.coordinator, name: "timer")

        UNUserNotificationCenter.current().delegate = context.coordinator

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = true
        webView.isOpaque = false
        let bg = UIColor(red: 15/255, green: 15/255, blue: 15/255, alpha: 1)
        webView.backgroundColor = bg
        webView.scrollView.backgroundColor = bg

        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "www") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UNUserNotificationCenterDelegate {
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "haptic":
                DispatchQueue.main.async { Self.playTimerDoneHaptic() }
            case "timer":
                guard let body = message.body as? [String: Any],
                      let action = body["action"] as? String else { return }
                let seconds = (body["seconds"] as? Double) ?? (body["seconds"] as? Int).map(Double.init) ?? 0
                let label = body["label"] as? String ?? "Pomodoro"
                switch action {
                case "schedule":
                    TimerNotification.requestPermission()
                    TimerNotification.schedule(seconds: seconds, label: label)
                case "cancel", "stop":
                    TimerNotification.cancel()
                default:
                    break
                }
            default:
                break
            }
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            Self.playTimerDoneHaptic()
            TimerNotification.cancel()
            completionHandler([.banner, .sound])
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            Self.playTimerDoneHaptic()
            completionHandler()
        }

        private static func playTimerDoneHaptic() {
            let note = UINotificationFeedbackGenerator()
            note.prepare()
            note.notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                let heavy = UIImpactFeedbackGenerator(style: .heavy)
                heavy.prepare()
                heavy.impactOccurred()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                let heavy = UIImpactFeedbackGenerator(style: .heavy)
                heavy.prepare()
                heavy.impactOccurred()
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               navigationAction.navigationType == .linkActivated,
               let scheme = url.scheme, scheme == "http" || scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                UIApplication.shared.open(url)
            }
            return nil
        }
    }
}
