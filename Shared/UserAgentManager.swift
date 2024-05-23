import Logging
#if !os(tvOS)
    import WebKit
#endif

final class UserAgentManager {
    static let shared = UserAgentManager()

    private(set) var userAgent: String
    #if !os(tvOS)
        private var webView: WKWebView?
    #endif

    private init() {
        /*
         In case an error occurs while retrieving the actual User-Agent, and on tvOS,
         we set a default User-Agent value that represents a commonly used User-Agent.
         */

        userAgent = "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; Trident/5.0)"
        #if !os(tvOS)
            webView = WKWebView()
            webView?.evaluateJavaScript("navigator.userAgent") { [weak self] result, _ in
                if let userAgent = result as? String {
                    DispatchQueue.main.async {
                        self?.userAgent = userAgent
                        Logger(label: "stream.yattee.userAgentManager").info("User-Agent: \(userAgent)")
                    }
                } else {
                    Logger(label: "stream.yattee.userAgentManager").warning("Failed to update User-Agent.")
                }
            }
        #else
            Logger(label: "stream.yattee.userAgentManager.tvOS").info("User-Agent: \(userAgent)")
        #endif
    }
}
