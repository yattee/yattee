import SwiftUI

struct InstanceForm: View {
    @Binding var savedInstanceID: Instance.ID?

    @State private var name = ""
    @State private var url = ""
    @State private var app = VideosApp.invidious

    @State private var isValid = false
    @State private var isValidated = false
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var validationDebounce = Debounce()

    @FocusState private var nameFieldFocused: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            Group {
                header

                form

                footer
            }
            .frame(maxWidth: 1000)
        }
        .onChange(of: app) { _ in validate() }
        .onChange(of: url) { _ in validate() }
        .onAppear(perform: initializeForm)
        #if os(iOS)
            .padding(.vertical)
        #elseif os(tvOS)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .background(.thickMaterial)
        #else
            .frame(width: 400, height: 190)
        #endif
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Add Instance")
                .font(.title2.bold())

            Spacer()

            Button("Cancel") {
                dismiss()
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
            Picker("Application", selection: $app) {
                ForEach(VideosApp.allCases, id: \.self) { app in
                    Text(app.rawValue.capitalized).tag(app)
                }
            }
            .pickerStyle(.segmented)

            TextField("Name", text: $name, prompt: Text("Instance Name (optional)"))
                .focused($nameFieldFocused)

            TextField("API URL", text: $url, prompt: Text("https://invidious.home.net"))

            #if !os(macOS)
                .autocapitalization(.none)
                .keyboardType(.URL)
            #endif
        }
    }

    private var footer: some View {
        HStack(alignment: .center) {
            AccountValidationStatus(isValid: $isValid, isValidated: $isValidated, isValidating: $isValidating, error: $validationError)

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

    func initializeForm() {
        nameFieldFocused = true
    }

    func submitForm() {
        guard isValid else {
            return
        }

        savedInstanceID = InstancesModel.add(app: app, name: name, url: url).id

        dismiss()
    }
}

struct InstanceFormView_Previews: PreviewProvider {
    static var previews: some View {
        InstanceForm(savedInstanceID: .constant(nil))
    }
}
