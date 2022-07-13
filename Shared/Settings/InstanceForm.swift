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

    var body: some View {
        VStack(alignment: .leading) {
            Group {
                header

                form

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
            .frame(width: 400, height: 150)
        #endif
    }

    private var header: some View {
        HStack(alignment: .center) {
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

            TextField("URL", text: $url)

            #if !os(macOS)
                .autocapitalization(.none)
                .keyboardType(.URL)
            #endif
        }
    }

    private var footer: some View {
        HStack(alignment: .center) {
            AccountValidationStatus(
                app: $app,
                isValid: $isValid,
                isValidated: $isValidated,
                isValidating: $isValidating,
                error: $validationError
            )

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
        guard isValid, let app = app else {
            return
        }

        savedInstanceID = InstancesModel.add(app: app, name: name, url: url).id

        presentationMode.wrappedValue.dismiss()
    }
}

struct InstanceFormView_Previews: PreviewProvider {
    static var previews: some View {
        InstanceForm(savedInstanceID: .constant(nil))
    }
}
