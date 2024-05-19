import Logging
import WebKit

final class UserAgentManager {
    static let shared = UserAgentManager()

    private(set) var userAgent: String
    private var webView: WKWebView?

    private init() {
        // In case an error occurs while retrieving the actual User-Agent,
        // we set a default User-Agent value that represents a commonly used User-Agent.
        userAgent = "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0)"

        webView = WKWebView()
        webView?.evaluateJavaScript("navigator.userAgent") { [weak self] result, _ in
            if let userAgent = result as? String {
                DispatchQueue.main.async {
                    self?.userAgent = userAgent
                    Logger(label: "stream.yattee.userAgentManager").info("User-Agent: \(userAgent)")
                    print("User-Agent updated: \(userAgent)")
                }
            } else {
                Logger(label: "stream.yattee.userAgentManager").warning("Failed to update User-Agent.")
            }
        }
    }
}
