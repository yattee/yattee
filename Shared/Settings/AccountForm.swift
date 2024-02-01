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
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack {
            Group {
                header
                form
                #if os(macOS)
                    VStack {
                        validationStatus
                    }
                    .frame(minHeight: 60, alignment: .topLeading)
                    .padding(.horizontal, 15)
                #endif
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
        .frame(width: 400, height: 180)
        .padding(.vertical)
        #endif
    }

    var header: some View {
        HStack {
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
                }
            #else
                formFields
            #endif
        }
        .onChange(of: username) { _ in validate() }
        .onChange(of: password) { _ in validate() }
    }

    @ViewBuilder var formFields: some View {
        TextField("Username", text: $username)
        #if !os(macOS)
            .autocapitalization(.none)
        #endif
            .disableAutocorrection(true)
        SecureField("Password", text: $password)

        #if os(tvOS)
            VStack {
                validationStatus
            }
            .frame(minHeight: 100)
        #elseif os(iOS)
            validationStatus
        #endif
    }

    @ViewBuilder var validationStatus: some View {
        Section {
            if username.isEmpty || password.isEmpty {
                Text("Enter account credentials to connect...")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.secondary)
            } else {
                AccountValidationStatus(
                    app: .constant(instance.app),
                    isValid: $isValid,
                    isValidated: $isValidated,
                    isValidating: $isValidating,
                    error: $validationError
                )
            }
        }
    }

    var footer: some View {
        HStack {
            Spacer()

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

        guard !username.isEmpty, !password.isEmpty else {
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

        let account = AccountsModel.add(instance: instance, id: nil, name: name, username: username, password: password)
        selectedAccount?.wrappedValue = account

        presentationMode.wrappedValue.dismiss()
    }

    private var validator: AccountValidator {
        AccountValidator(
            app: .constant(instance.app),
            url: instance.apiURLString,
            account: Account(instanceID: instance.id, urlString: instance.apiURLString, username: username, password: password),
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
