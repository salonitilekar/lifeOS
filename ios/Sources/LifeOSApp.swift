import SwiftUI
import WebKit
import UserNotifications

@main
struct LifeOSApp: App {
    init() {
        LifeOSNotifications.requestPermission()
    }

    var body: some Scene {
        WindowGroup {
            WebView()
                .ignoresSafeArea()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    _ = HealthURLHandler.handle(url)
                }
        }
    }
}

private enum LifeOSNotifications {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func notificationContent(title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        return content
    }
}

private enum TimerNotification {
    static let id = "lifeos.pomodoro.done"

    static func schedule(seconds: TimeInterval, label: String) {
        cancel()
        guard seconds > 0 else { return }

        let content = LifeOSNotifications.notificationContent(
            title: "Pomodoro done",
            body: label.isEmpty ? "Lock-in complete — take a break." : "\(label) — 25 minutes up."
        )

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

private enum BlockNotification {
    static let prefix = "lifeos.block."

    static func cancelAll(completion: (() -> Void)? = nil) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            completion?()
        }
    }

    static func schedule(blocks: [[String: Any]]) {
        cancelAll {
            let center = UNUserNotificationCenter.current()
            for block in blocks {
                guard let id = block["id"] as? String,
                      let atMs = (block["at"] as? Double) ?? (block["at"] as? Int).map(Double.init),
                      let title = block["title"] as? String,
                      let body = block["body"] as? String else { continue }

                let date = Date(timeIntervalSince1970: atMs / 1000.0)
                guard date.timeIntervalSinceNow > 1 else { continue }

                let content = LifeOSNotifications.notificationContent(title: title, body: body)
                let comps = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: date
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let request = UNNotificationRequest(
                    identifier: prefix + id,
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
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
        config.userContentController.add(context.coordinator, name: "blocks")
        config.userContentController.add(context.coordinator, name: "health")

        UNUserNotificationCenter.current().delegate = context.coordinator

        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.webView = webView
        WebViewBridge.shared.attach(webView)
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
        weak var webView: WKWebView?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "haptic":
                DispatchQueue.main.async { Self.playNotificationHaptic() }
            case "timer":
                guard let body = message.body as? [String: Any],
                      let action = body["action"] as? String else { return }
                let seconds = (body["seconds"] as? Double) ?? (body["seconds"] as? Int).map(Double.init) ?? 0
                let label = body["label"] as? String ?? "Pomodoro"
                switch action {
                case "schedule":
                    LifeOSNotifications.requestPermission()
                    TimerNotification.schedule(seconds: seconds, label: label)
                case "cancel", "stop":
                    TimerNotification.cancel()
                default:
                    break
                }
            case "blocks":
                guard let body = message.body as? [String: Any],
                      let action = body["action"] as? String else { return }
                switch action {
                case "schedule":
                    LifeOSNotifications.requestPermission()
                    if let blocks = body["blocks"] as? [[String: Any]] {
                        BlockNotification.schedule(blocks: blocks)
                    }
                case "cancel":
                    BlockNotification.cancelAll()
                default:
                    break
                }
            case "health":
                guard let body = message.body as? [String: Any],
                      let action = body["action"] as? String,
                      action == "sync" else { return }
                let webView = message.webView ?? self.webView
                HealthKitManager.syncSteps { result in
                    DispatchQueue.main.async {
                        guard let webView else { return }
                        switch result {
                        case .success(let days):
                            guard let jsonData = try? JSONSerialization.data(withJSONObject: days),
                                  let json = String(data: jsonData, encoding: .utf8) else {
                                webView.evaluateJavaScript(
                                    "window.onHealthStepsError&&window.onHealthStepsError({code:'encode'})"
                                )
                                return
                            }
                            webView.evaluateJavaScript(
                                "window.onHealthSteps&&window.onHealthSteps({days:\(json)})"
                            )
                        case .failure(let error):
                            webView.evaluateJavaScript(
                                "window.onHealthStepsError&&window.onHealthStepsError({code:'\(error.code)'})"
                            )
                        }
                    }
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
            Self.playNotificationHaptic()
            if notification.request.identifier == TimerNotification.id {
                TimerNotification.cancel()
            }
            completionHandler([.banner, .sound])
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            Self.playNotificationHaptic()
            completionHandler()
        }

        private static func playNotificationHaptic() {
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            WebViewBridge.shared.attach(webView)
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
