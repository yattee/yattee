import Alamofire
import Foundation
import Siesta
import SwiftUI

final class AccountValidator: Service {
    let app: Binding<VideosApp?>
    let url: String
    let account: Account!

    var formObjectID: Binding<String>
    var isValid: Binding<Bool>
    var isValidated: Binding<Bool>
    var isValidating: Binding<Bool>
    var error: Binding<String?>?
    var ignoreCertificateError: Binding<Bool>?

    private var appsToValidateInstance = VideosApp.allCases

    init(
        app: Binding<VideosApp?>,
        url: String,
        account: Account? = nil,
        id: Binding<String>,
        isValid: Binding<Bool>,
        isValidated: Binding<Bool>,
        isValidating: Binding<Bool>,
        error: Binding<String?>? = nil,
        ignoreCertificateError: Binding<Bool>? = nil
    ) {
        self.app = app
        self.url = url
        self.account = account
        formObjectID = id
        self.isValid = isValid
        self.isValidated = isValidated
        self.isValidating = isValidating
        self.error = error
        self.ignoreCertificateError = ignoreCertificateError

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.requestCachePolicy = .reloadIgnoringLocalCacheData

        let customSession = URLSession(configuration: sessionConfig,
                                       delegate: ignoreCertificateError?.wrappedValue == true ? PermissiveDelegate() : nil,
                                       delegateQueue: OperationQueue.main)

        super.init(baseURL: url, networking: URLSessionProvider(session: customSession))

        configure()
    }

    func configure() {
        configure {
            $0.pipeline[.parsing].add(SwiftyJSONTransformer, contentTypes: ["*/json"])
        }

        configure("/login", requestMethods: [.post]) {
            $0.headers["Content-Type"] = "application/json"
        }
    }

    func instanceValidationResource(_ app: VideosApp) -> Resource {
        switch app {
        case .invidious:
            return resource("/api/v1/videos/dQw4w9WgXcQ")

        case .piped:
            return resource("/streams/dQw4w9WgXcQ")

        case .peerTube:
            // TODO: fixme
            return resource("")

        case .local:
            return resource("")
        }
    }

    func validateInstance() {
        reset()

        guard let app = appsToValidateInstance.popLast() else { return }
        tryValidatingUsing(app)
    }

    func tryValidatingUsing(_ app: VideosApp) {
        instanceValidationResource(app)
            .load()
            .onSuccess { response in
                guard self.url == self.formObjectID.wrappedValue else {
                    return
                }

                guard !response.json.isEmpty else {
                    if app == .piped {
                        if response.text.contains("property=\"og:title\" content=\"Piped\"") {
                            self.isValid.wrappedValue = false
                            self.isValidated.wrappedValue = true
                            self.isValidating.wrappedValue = false
                            self.error?.wrappedValue = "Trying to use Piped front-end URL, you need to use URL for Piped API instead"
                            return
                        }
                    }

                    guard let nextApp = self.appsToValidateInstance.popLast() else {
                        self.isValid.wrappedValue = false
                        self.isValidated.wrappedValue = true
                        self.isValidating.wrappedValue = false
                        return
                    }

                    self.tryValidatingUsing(nextApp)
                    return
                }

                let json = response.json.dictionaryValue
                let author = app == .invidious ? json["author"] : json["uploader"]

                if author == "Rick Astley" {
                    self.app.wrappedValue = app
                    self.isValid.wrappedValue = true
                    self.error?.wrappedValue = nil
                } else {
                    self.isValid.wrappedValue = false
                }
                self.isValidated.wrappedValue = true
                self.isValidating.wrappedValue = false
            }
            .onFailure { error in
                guard self.url == self.formObjectID.wrappedValue else {
                    return
                }

                if self.appsToValidateInstance.isEmpty {
                    self.isValidating.wrappedValue = false
                    self.isValidated.wrappedValue = true
                    self.isValid.wrappedValue = false
                    self.error?.wrappedValue = error.userMessage
                } else {
                    guard let app = self.appsToValidateInstance.popLast() else { return }
                    self.tryValidatingUsing(app)
                }
            }
    }

    func validateAccount() {
        reset()

        switch app.wrappedValue {
        case .invidious:
            validateInvidiousAccount()
        case .piped:
            validatePipedAccount()
        default:
            setValidationResult(false)
        }
    }

    func validateInvidiousAccount() {
        guard let username = account?.username,
              let password = account?.password
        else {
            setValidationResult(false)

            return
        }

        AF
            .request(login.url, method: .post, parameters: ["email": username, "password": password], encoding: URLEncoding.default)
            .redirect(using: .doNotFollow)
            .response { response in
                guard let headers = response.response?.headers,
                      let cookies = headers["Set-Cookie"]
                else {
                    self.setValidationResult(false)
                    return
                }

                let sidRegex = #"SID=(?<sid>[^;]*);"#
                guard let sidRegex = try? NSRegularExpression(pattern: sidRegex),
                      let match = sidRegex.matches(in: cookies, range: NSRange(cookies.startIndex..., in: cookies)).first
                else {
                    self.setValidationResult(false)
                    return
                }

                let matchRange = match.range(withName: "sid")

                if let substringRange = Range(matchRange, in: cookies) {
                    let sid = String(cookies[substringRange])
                    if !sid.isEmpty {
                        self.setValidationResult(true)
                    }
                } else {
                    self.setValidationResult(false)
                }
            }
    }

    func validatePipedAccount() {
        guard let request = accountRequest else {
            setValidationResult(false)

            return
        }

        request.onSuccess { response in
            guard self.account!.username == self.formObjectID.wrappedValue else {
                return
            }

            switch self.app.wrappedValue {
            case .invidious:
                self.isValid.wrappedValue = true
            case .piped:
                let error = response.json.dictionaryValue["error"]?.string
                let token = response.json.dictionaryValue["token"]?.string
                self.isValid.wrappedValue = error?.isEmpty ?? !(token?.isEmpty ?? true)
                self.error!.wrappedValue = error
            default:
                return
            }
        }
        .onFailure { _ in
            guard self.account!.username == self.formObjectID.wrappedValue else {
                return
            }

            self.isValid.wrappedValue = false
        }
        .onCompletion { _ in
            self.isValidated.wrappedValue = true
            self.isValidating.wrappedValue = false
        }
    }

    func setValidationResult(_ result: Bool) {
        isValid.wrappedValue = result
        isValidated.wrappedValue = true
        isValidating.wrappedValue = false
    }

    var accountRequest: Siesta.Request? {
        switch app.wrappedValue {
        case .invidious:
            guard let password = account.password else { return nil }
            return login.request(.post, urlEncoded: ["email": account.username, "password": password])
        case .piped:
            return login.request(.post, json: ["username": account.username, "password": account.password])
        default:
            return nil
        }
    }

    func reset() {
        appsToValidateInstance = VideosApp.allCases
        app.wrappedValue = nil
        isValid.wrappedValue = false
        isValidated.wrappedValue = false
        isValidating.wrappedValue = false
        error?.wrappedValue = nil
    }

    var login: Resource {
        resource("/login")
    }

    var videoResourceBasePath: String {
        app.wrappedValue == .invidious ? "/api/v1/videos" : "/streams"
    }

    var neverGonnaGiveYouUp: Resource {
        resource("\(videoResourceBasePath)/dQw4w9WgXcQ")
    }
}

final class PermissiveDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!))
        }
    }
}
