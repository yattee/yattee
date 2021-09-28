import Foundation
import Siesta
import SwiftUI

final class AccountValidator: Service {
    let url: String
    let account: Instance.Account?

    var formObjectID: Binding<String>
    var isValid: Binding<Bool>
    var isValidated: Binding<Bool>
    var isValidating: Binding<Bool>
    var error: Binding<String?>?

    init(
        url: String,
        account: Instance.Account? = nil,
        id: Binding<String>,
        isValid: Binding<Bool>,
        isValidated: Binding<Bool>,
        isValidating: Binding<Bool>,
        error: Binding<String?>? = nil
    ) {
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
        configure("/api/v1/auth/feed", requestMethods: [.get]) {
            guard self.account != nil else {
                return
            }

            $0.headers["Cookie"] = self.cookieHeader
        }
    }

    func validateInstance() {
        reset()

        stats
            .load()
            .onSuccess { _ in
                guard self.url == self.formObjectID.wrappedValue else {
                    return
                }

                self.isValid.wrappedValue = true
                self.error?.wrappedValue = nil
            }
            .onFailure { error in
                guard self.url == self.formObjectID.wrappedValue else {
                    return
                }

                self.isValid.wrappedValue = false
                self.error?.wrappedValue = error.userMessage
            }
            .onCompletion { _ in
                self.isValidated.wrappedValue = true
                self.isValidating.wrappedValue = false
            }
    }

    func validateAccount() {
        reset()

        feed
            .load()
            .onSuccess { _ in
                guard self.account!.sid == self.formObjectID.wrappedValue else {
                    return
                }

                self.isValid.wrappedValue = true
            }
            .onFailure { _ in
                guard self.account!.sid == self.formObjectID.wrappedValue else {
                    return
                }

                self.isValid.wrappedValue = false
            }
            .onCompletion { _ in
                self.isValidated.wrappedValue = true
                self.isValidating.wrappedValue = false
            }
    }

    func reset() {
        isValid.wrappedValue = false
        isValidated.wrappedValue = false
        isValidating.wrappedValue = false
        error?.wrappedValue = nil
    }

    var cookieHeader: String {
        "SID=\(account!.sid)"
    }

    var stats: Resource {
        resource("/api/v1/stats")
    }

    var feed: Resource {
        resource("/api/v1/auth/feed")
    }
}
