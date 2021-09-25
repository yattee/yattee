import Foundation
import Siesta
import SwiftUI

final class InstanceAccountValidator: Service {
    let url: String
    let account: Instance.Account?

    var formObjectID: Binding<String>
    var valid: Binding<Bool>
    var validated: Binding<Bool>
    var error: Binding<String?>?

    init(
        url: String,
        account: Instance.Account? = nil,
        formObjectID: Binding<String>,
        valid: Binding<Bool>,
        validated: Binding<Bool>,
        error: Binding<String?>? = nil
    ) {
        self.url = url
        self.account = account
        self.formObjectID = formObjectID
        self.valid = valid
        self.validated = validated
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

                self.valid.wrappedValue = true
                self.error?.wrappedValue = nil
                self.validated.wrappedValue = true
            }
            .onFailure { error in
                guard self.url == self.formObjectID.wrappedValue else {
                    return
                }

                self.valid.wrappedValue = false
                self.error?.wrappedValue = error.userMessage
                self.validated.wrappedValue = true
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

                self.valid.wrappedValue = true
                self.validated.wrappedValue = true
            }
            .onFailure { _ in
                guard self.account!.sid == self.formObjectID.wrappedValue else {
                    return
                }

                self.valid.wrappedValue = false
                self.validated.wrappedValue = true
            }
    }

    func reset() {
        valid.wrappedValue = false
        validated.wrappedValue = false
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
