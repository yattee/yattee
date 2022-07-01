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

    private var appsToValidateInstance = VideosApp.allCases

    init(
        app: Binding<VideosApp?>,
        url: String,
        account: Account? = nil,
        id: Binding<String>,
        isValid: Binding<Bool>,
        isValidated: Binding<Bool>,
        isValidating: Binding<Bool>,
        error: Binding<String?>? = nil
    ) {
        self.app = app
        self.url = url
        self.account = account
        formObjectID = id
        self.isValid = isValid
        self.isValidated = isValidated
        self.isValidating = isValidating
        self.error = error

        super.init(baseURL: url)
        configure()
    }

    func configure() {
        configure {
            $0.pipeline[.parsing].add(SwiftyJSONTransformer, contentTypes: ["*/json"])
        }

        configure("/api/v1/auth/feed", requestMethods: [.get]) {
            guard self.account != nil else {
                return
            }

            $0.headers["Cookie"] = self.invidiousCookieHeader
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
                    guard let app = self.appsToValidateInstance.popLast() else {
                        self.isValid.wrappedValue = false
                        self.isValidated.wrappedValue = true
                        self.isValidating.wrappedValue = false
                        return
                    }

                    self.tryValidatingUsing(app)
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

        guard let request = accountRequest else {
            isValid.wrappedValue = false
            isValidated.wrappedValue = true
            isValidating.wrappedValue = false

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

    var accountRequest: Request? {
        switch app.wrappedValue {
        case .invidious:
            return feed.load()
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

    var invidiousCookieHeader: String {
        "SID=\(account.username)"
    }

    var login: Resource {
        resource("/login")
    }

    var feed: Resource {
        resource("/api/v1/auth/feed")
    }

    var videoResourceBasePath: String {
        app.wrappedValue == .invidious ? "/api/v1/videos" : "/streams"
    }

    var neverGonnaGiveYouUp: Resource {
        resource("\(videoResourceBasePath)/dQw4w9WgXcQ")
    }
}
