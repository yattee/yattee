import SwiftUI

struct ImportSettingsAccountRow: View {
    var account: Account
    var fileModel: ImportSettingsFileModel

    @State private var password = ""

    @State private var isValid = false
    @State private var isValidated = false
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var validationDebounce = Debounce()

    @ObservedObject private var model = ImportSettingsSheetViewModel.shared

    func afterValidation() {
        if isValid {
            model.importableAccounts.insert(account.id)
            model.selectedAccounts.insert(account.id)
            model.importableAccountsPasswords[account.id] = password
        } else {
            model.selectedAccounts.remove(account.id)
            model.importableAccounts.remove(account.id)
            model.importableAccountsPasswords.removeValue(forKey: account.id)
        }
    }

    var body: some View {
        #if os(tvOS)
            row
        #else
            Button(action: { model.toggleAccount(account, accounts: accounts) }) {
                row
            }
            .buttonStyle(.plain)
        #endif
    }

    var row: some View {
        let accountExists = AccountsModel.shared.find(account.id) != nil

        return VStack(alignment: .leading) {
            HStack {
                Text(account.username)
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
                    .opacity(isChecked ? 1 : 0)
            }
            Text(account.instance?.description ?? "")
                .font(.caption)
                .foregroundColor(.secondary)

            Group {
                if let instanceID = account.instanceID {
                    if accountExists {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Color("AppRedColor"))
                            Text("Account already exists")
                        }
                    } else {
                        Group {
                            if InstancesModel.shared.find(instanceID) != nil || InstancesModel.shared.findByURLString(account.urlString) != nil {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Custom Location already exists")
                                }
                            } else if model.selectedInstances.contains(instanceID) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Custom Location selected for import")
                                }
                            } else {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                    Text("Custom Location not selected for import")
                                }
                                .foregroundColor(Color("AppRedColor"))
                            }
                        }
                        .frame(minHeight: 20)

                        if account.password.isNil || account.password!.isEmpty {
                            Group {
                                if password.isEmpty {
                                    HStack {
                                        Image(systemName: "key")
                                        Text("Password required to import")
                                    }
                                    .foregroundColor(Color("AppRedColor"))
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
                            .frame(minHeight: 20)
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)

                                Text("Password saved in import file")
                            }
                        }
                    }
                }
            }
            .foregroundColor(.primary)
            .font(.caption)
            .padding(.vertical, 2)

            if !accountExists && (account.password.isNil || account.password!.isEmpty) {
                SecureField("Password", text: $password)
                    .onChange(of: password) { _ in validate() }
                #if !os(tvOS)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onChange(of: isValid) { _ in afterValidation() }
        .animation(nil, value: isChecked)
    }

    var isChecked: Bool {
        model.isSelectedForImport(account)
    }

    var locationsSettingsGroupImporter: LocationsSettingsGroupImporter? {
        fileModel.locationsSettingsGroupImporter
    }

    var accounts: [Account] {
        fileModel.locationsSettingsGroupImporter?.accounts ?? []
    }

    private var instance: Instance! {
        (fileModel.locationsSettingsGroupImporter?.instances ?? []).first { $0.id == account.instanceID }
    }

    private var validator: AccountValidator {
        AccountValidator(
            app: .constant(instance.app),
            url: instance.apiURLString,
            account: Account(instanceID: instance.id, urlString: instance.apiURLString, username: account.username, password: password),
            id: .constant(account.username),
            isValid: $isValid,
            isValidated: $isValidated,
            isValidating: $isValidating,
            error: $validationError
        )
    }

    private func validate() {
        isValid = false
        validationDebounce.invalidate()

        guard !account.username.isEmpty, !password.isEmpty else {
            validator.reset()
            return
        }

        isValidating = true

        validationDebounce.debouncing(1) {
            validator.validateAccount()
        }
    }
}

struct ImportSettingsAccountRow_Previews: PreviewProvider {
    static var previews: some View {
        let fileModel = ImportSettingsFileModel()
        fileModel.loadData(URL(string: "https://gist.githubusercontent.com/arekf/578668969c9fdef1b3828bea864c3956/raw/f794a95a20261bcb1145e656c8dda00bea339e2a/yattee-recents.yatteesettings")!)

        return List {
            ImportSettingsAccountRow(
                account: .init(name: "arekf", urlString: "https://instance.com", username: "arekf"),
                fileModel: fileModel
            )
            ImportSettingsAccountRow(
                account: .init(name: "arekf", urlString: "https://instance.com", username: "arekf", password: "a"),
                fileModel: fileModel
            )
        }
    }
}
