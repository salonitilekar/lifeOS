import Foundation
import WebKit

final class WebViewBridge {
    static let shared = WebViewBridge()

    weak var webView: WKWebView?
    private var pendingJavaScript: String?

    func attach(_ webView: WKWebView) {
        self.webView = webView
        flushPending()
    }

    func importHealthDays(_ days: [String: Int]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: days),
              let json = String(data: jsonData, encoding: .utf8) else { return }
        runJavaScript("window.onHealthSteps&&window.onHealthSteps({days:\(json),source:'shortcut'})")
    }

    func importScreenDays(_ days: [String: Int]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: days),
              let json = String(data: jsonData, encoding: .utf8) else { return }
        runJavaScript("window.onScreenMinutes&&window.onScreenMinutes({days:\(json),source:'shortcut'})")
    }

    func runJavaScript(_ script: String) {
        if let webView {
            webView.evaluateJavaScript(script)
            pendingJavaScript = nil
        } else {
            pendingJavaScript = script
        }
    }

    private func flushPending() {
        guard let webView, let script = pendingJavaScript else { return }
        webView.evaluateJavaScript(script)
        pendingJavaScript = nil
    }
}

enum HealthURLHandler {
    static func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "lifeos" else { return false }
        let host = url.host?.lowercased() ?? ""

        switch host {
        case "health":
            let days = parseDayCounts(from: url)
            guard !days.isEmpty else { return false }
            WebViewBridge.shared.importHealthDays(days)
            return true
        case "screen":
            let days = parseDayCounts(from: url)
            guard !days.isEmpty else { return false }
            WebViewBridge.shared.importScreenDays(days)
            return true
        default:
            return false
        }
    }

    private static func parseDayCounts(from url: URL) -> [String: Int] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let lookup = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })

        var days: [String: Int] = [:]
        let calendar = Calendar.current
        let today = Date()
        let todayStart = calendar.startOfDay(for: today)

        if let value = lookup["today"], let count = Int(value) {
            days[dateKey(for: today)] = max(0, count)
        } else if let value = lookup["steps"], let count = Int(value) {
            days[dateKey(for: today)] = max(0, count)
        } else if let value = lookup["minutes"], let count = Int(value) {
            days[dateKey(for: today)] = max(0, count)
        }

        if let value = lookup["yesterday"], let count = Int(value),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) {
            days[dateKey(for: yesterday)] = max(0, count)
        }

        for (key, value) in lookup where key != "today" && key != "yesterday" && key != "steps" && key != "minutes" {
            guard let count = Int(value) else { continue }
            days[key] = max(0, count)
        }

        return days
    }

    private static func dateKey(for date: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(year)-\(month)-\(day)"
    }
}
