import Defaults
import SwiftUI

struct AccountFormView: View {
    let instance: Instance
    var selectedAccount: Binding<Instance.Account?>?

    @State private var name = ""
    @State private var sid = ""

    @State private var isValid = false
    @State private var isValidated = false
    @State private var isValidating = false
    @State private var validationDebounce = Debounce()

    @FocusState private var focused: Bool

    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject<InstancesModel> private var instances

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
            .background(.thickMaterial)
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
                dismiss()
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
        .onAppear(perform: initializeForm)
        .onChange(of: sid) { _ in validate() }
    }

    var formFields: some View {
        Group {
            TextField("Name", text: $name, prompt: Text("Account Name (optional)"))
                .focused($focused)

            TextField("SID", text: $sid, prompt: Text("Invidious SID Cookie"))
        }
    }

    var footer: some View {
        HStack {
            ValidationStatusView(isValid: $isValid, isValidated: $isValidated, isValidating: $isValidating, error: .constant(nil))

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

    private func initializeForm() {
        focused = true
    }

    private func validate() {
        validationDebounce.invalidate()

        guard !sid.isEmpty else {
            validator.reset()
            return
        }

        isValidating = true

        validationDebounce.debouncing(1) {
            validator.validateInvidiousAccount()
        }
    }

    private func submitForm() {
        guard isValid else {
            return
        }

        let account = instances.addAccount(instance: instance, name: name, sid: sid)
        selectedAccount?.wrappedValue = account

        dismiss()
    }

    private var validator: AccountValidator {
        AccountValidator(
            app: .constant(instance.app),
            url: instance.url,
            account: Instance.Account(instanceID: instance.id, url: instance.url, sid: sid),
            id: $sid,
            isValid: $isValid,
            isValidated: $isValidated,
            isValidating: $isValidating
        )
    }
}

struct AccountFormView_Previews: PreviewProvider {
    static var previews: some View {
        AccountFormView(instance: Instance.fixture)
    }
}
