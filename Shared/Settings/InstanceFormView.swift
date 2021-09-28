import SwiftUI

struct InstanceFormView: View {
    @Binding var savedInstanceID: Instance.ID?

    @State private var name = ""
    @State private var url = ""

    @State private var valid = false
    @State private var validated = false
    @State private var validationError: String?
    @State private var validationDebounce = Debounce()

    @FocusState private var nameFieldFocused: Bool

    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject<InstancesModel> private var instancesModel

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
        .onAppear(perform: initializeForm)
        #if os(iOS)
            .padding(.vertical)
        #elseif os(tvOS)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .background(.thickMaterial)
        #else
            .frame(width: 400, height: 150)
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
            TextField("Name", text: $name, prompt: Text("Instance Name (optional)"))

                .focused($nameFieldFocused)

            TextField("URL", text: $url, prompt: Text("https://invidious.home.net"))
        }
    }

    private var footer: some View {
        HStack(alignment: .center) {
            validationStatus

            Spacer()

            Button("Save", action: submitForm)
                .disabled(!valid)
            #if !os(tvOS)
                .keyboardShortcut(.defaultAction)
            #endif
        }
        #if os(tvOS)
            .padding(.top, 30)
        #endif
        .padding(.horizontal)
    }

    private var validationStatus: some View {
        HStack(spacing: 4) {
            Image(systemName: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(valid ? .green : .red)
            VStack(alignment: .leading) {
                Text(valid ? "Connected successfully" : "Connection failed")
                if !valid {
                    Text(validationError ?? "Unknown Error")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .truncationMode(.tail)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 35)
        }
        .opacity(validated ? 1 : 0)
    }

    var validator: AccountValidator {
        AccountValidator(
            url: url,
            id: $url,
            valid: $valid,
            validated: $validated,
            error: $validationError
        )
    }

    func validate() {
        validationDebounce.invalidate()

        guard !url.isEmpty else {
            validator.reset()
            return
        }

        validationDebounce.debouncing(2) {
            validator.validateInstance()
        }
    }

    func initializeForm() {
        nameFieldFocused = true
    }

    func submitForm() {
        guard valid else {
            return
        }

        savedInstanceID = instancesModel.add(name: name, url: url).id

        dismiss()
    }
}

struct InstanceFormView_Previews: PreviewProvider {
    static var previews: some View {
        InstanceFormView(savedInstanceID: .constant(nil))
    }
}
