import Defaults
import SwiftUI

struct AccountFormView: View {
    let instance: Instance
    var selectedAccount: Binding<Instance.Account?>?

    @State private var name = ""
    @State private var sid = ""

    @State private var valid = false
    @State private var validated = false

    @FocusState private var focused: Bool

    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject<InstancesModel> private var instances

    var body: some View {
        VStack {
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

            Form {
                TextField("Name", text: $name, prompt: Text("Account Name (optional)"))
                    .focused($focused)

                TextField("SID", text: $sid, prompt: Text("Invidious SID Cookie"))
            }
            .onAppear(perform: initializeForm)
            .onChange(of: sid) { _ in validate() }

            #if os(macOS)
                .padding(.horizontal)
            #endif

            HStack {
                HStack(spacing: 4) {
                    Image(systemName: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(valid ? .green : .red)
                    VStack(alignment: .leading) {
                        Text(valid ? "Account found" : "Invalid account details")
                    }
                }
                .opacity(validated ? 1 : 0)
                Spacer()

                Button("Save", action: submitForm)
                    .disabled(!valid)
                #if !os(tvOS)
                    .keyboardShortcut(.defaultAction)
                #endif
            }
            .frame(minHeight: 35)
            .padding(.horizontal)
        }

        #if os(iOS)
            .padding(.vertical)
        #else
            .frame(width: 400, height: 145)
        #endif
    }

    func initializeForm() {
        focused = true
    }

    func validate() {
        guard !sid.isEmpty else {
            validator.reset()
            return
        }

        validator.validateAccount()
    }

    func submitForm() {
        guard valid else {
            return
        }

        let account = instances.addAccount(instance: instance, name: name, sid: sid)
        selectedAccount?.wrappedValue = account

        dismiss()
    }

    private var validator: InstanceAccountValidator {
        InstanceAccountValidator(
            url: instance.url,
            account: Instance.Account(url: instance.url, sid: sid),
            formObjectID: $sid,
            valid: $valid,
            validated: $validated
        )
    }
}

struct AccountFormView_Previews: PreviewProvider {
    static var previews: some View {
        AccountFormView(instance: Instance.fixture)
    }
}
