import Defaults
import SwiftUI

struct AccountForm: View {
    let instance: Instance
    var selectedAccount: Binding<Account?>?

    @State private var name = ""
    @State private var username = ""
    @State private var password = ""

    @State private var isValid = false
    @State private var isValidated = false
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var validationDebounce = Debounce()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack {
            Group {
                header
                form
                footer
            }
            .frame(maxWidth: 1000)
        }
        #if os(iOS)
        .padding(.vertical)
        #elseif os(tvOS)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .background(Color.background(scheme: colorScheme))
        #else
        .frame(width: 400, height: 145)
        #endif
    }

    var header: some View {
        HStack(alignment: .center) {
            Text("Add Account")
                .font(.title2.bold())

            Spacer()

            Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            }
            #if !os(tvOS)
            .keyboardShortcut(.cancelAction)
            #endif
        }
        .padding(.horizontal)
    }

    private var form: some View {
        Group {
            #if !os(tvOS)
                Form {
                    formFields
                    #if os(macOS)
                    .padding(.horizontal)
                    #endif

                    #if os(iOS)
                        helpButton
                    #endif
                }
            #else
                formFields
            #endif
        }
        .onChange(of: username) { _ in validate() }
        .onChange(of: password) { _ in validate() }
    }

    var helpButton: some View {
        Group {
            if instance.app == .invidious {
                Button {
                    openURL(URL(string: "https://github.com/yattee/yattee/wiki/Adding-Invidious-instance-and-account")!)
                } label: {
                    Label("How to add Invidious account?", systemImage: "questionmark.circle")
                    #if os(macOS)
                        .help("How to add Invidious account?")
                        .labelStyle(.iconOnly)
                    #endif
                }
            }
        }
    }

    var formFields: some View {
        Group {
            if !instance.app.accountsUsePassword {
                TextField("Name", text: $name)
            }

            TextField(usernamePrompt, text: $username)

            if instance.app.accountsUsePassword {
                SecureField("Password", text: $password)
            }
        }
    }

    var usernamePrompt: String {
        switch instance.app {
        case .invidious:
            return "SID Cookie"
        default:
            return "Username"
        }
    }

    var footer: some View {
        HStack {
            AccountValidationStatus(
                app: .constant(instance.app),
                isValid: $isValid,
                isValidated: $isValidated,
                isValidating: $isValidating,
                error: $validationError
            )

            Spacer()

            #if os(macOS)
                helpButton
            #endif

            Button("Save", action: submitForm)
                .disabled(!isValid)
            #if !os(tvOS)
                .keyboardShortcut(.defaultAction)
            #endif
        }
        .frame(minHeight: 35)
        #if os(tvOS)
            .padding(.top, 30)
        #endif
            .padding(.horizontal)
    }

    private func validate() {
        isValid = false
        validationDebounce.invalidate()

        let passwordIsValid = instance.app.accountsUsePassword ? !password.isEmpty : true

        guard !username.isEmpty, passwordIsValid else {
            validator.reset()
            return
        }

        isValidating = true

        validationDebounce.debouncing(1) {
            validator.validateAccount()
        }
    }

    private func submitForm() {
        guard isValid else {
            return
        }

        let account = AccountsModel.add(instance: instance, name: name, username: username, password: password)
        selectedAccount?.wrappedValue = account

        presentationMode.wrappedValue.dismiss()
    }

    private var validator: AccountValidator {
        AccountValidator(
            app: .constant(instance.app),
            url: instance.apiURL,
            account: Account(instanceID: instance.id, url: instance.apiURL, username: username, password: password),
            id: $username,
            isValid: $isValid,
            isValidated: $isValidated,
            isValidating: $isValidating,
            error: $validationError
        )
    }
}

struct AccountFormView_Previews: PreviewProvider {
    static var previews: some View {
        AccountForm(instance: Instance.fixture)
    }
}
