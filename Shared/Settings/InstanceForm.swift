import SwiftUI

struct InstanceForm: View {
    @Binding var savedInstanceID: Instance.ID?

    @State private var name = ""
    @State private var url = ""

    @State private var app: VideosApp?
    @State private var isValid = false
    @State private var isValidated = false
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var validationDebounce = Debounce()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode

    @ObservedObject private var accounts = AccountsModel.shared

    var body: some View {
        VStack(alignment: .leading) {
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
        .onChange(of: url) { _ in validate() }
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

    private var header: some View {
        HStack {
            Text("Add Location")
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

    private var formFields: some View {
        Group {
            TextField("Name", text: $name)

            TextField("Address", text: $url)

            #if !os(macOS)
                .autocapitalization(.none)
                .keyboardType(.URL)
            #endif
                .disableAutocorrection(true)

            #if os(tvOS)
                VStack {
                    validationStatus
                }
                .frame(minHeight: 100)
            #elseif os(iOS)
                validationStatus
            #endif
        }
    }

    @ViewBuilder var validationStatus: some View {
        Section {
            if url.isEmpty {
                Text("Enter location address to connect...")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.secondary)
            } else {
                AccountValidationStatus(
                    app: $app,
                    isValid: $isValid,
                    isValidated: $isValidated,
                    isValidating: $isValidating,
                    error: $validationError
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button("Save", action: submitForm)
                .disabled(!isValid)
            #if !os(tvOS)
                .keyboardShortcut(.defaultAction)
            #endif
        }
        #if os(tvOS)
        .padding(.top, 30)
        #endif
        .padding(.horizontal)
    }

    var validator: AccountValidator {
        AccountValidator(
            app: $app,
            url: url,
            id: $url,
            isValid: $isValid,
            isValidated: $isValidated,
            isValidating: $isValidating,
            error: $validationError
        )
    }

    func validate() {
        isValid = false
        validationDebounce.invalidate()

        guard !url.isEmpty else {
            validator.reset()
            return
        }

        isValidating = true

        validationDebounce.debouncing(2) {
            validator.validateInstance()
        }
    }

    func submitForm() {
        guard isValid, let app else {
            return
        }

        let savedInstance = InstancesModel.shared.add(app: app, name: name, url: url)
        savedInstanceID = savedInstance.id

        if accounts.isEmpty {
            accounts.setCurrent(savedInstance.anonymousAccount)
        }

        presentationMode.wrappedValue.dismiss()
    }
}

struct InstanceFormView_Previews: PreviewProvider {
    static var previews: some View {
        InstanceForm(savedInstanceID: .constant(nil))
    }
}
