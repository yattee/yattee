import SwiftUI

struct AccountsView: View {
    @StateObject private var model = AccountsViewModel()
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        #if os(macOS)
            VStack(alignment: .leading) {
                closeButton
                    .padding([.leading, .top])

                list
            }
            .frame(minWidth: 500, maxWidth: 800, minHeight: 700, maxHeight: 1200)

        #else
            NavigationView {
                list
                #if os(iOS)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        closeButton
                    }
                }
                #endif
                .navigationTitle("Accounts")
            }
            #if os(tvOS)
            .frame(maxWidth: 1000)
            #endif
        #endif
    }

    var list: some View {
        List {
            if !model.accounts.isEmpty {
                Section(header: Text("Your Accounts")) {
                    ForEach(model.sortedAccounts) { account in
                        accountButton(account)
                    }
                }
            }

            if !model.instances.isEmpty {
                Section(header: Text("Browse without account")) {
                    ForEach(model.instances) { instance in
                        accountButton(instance.anonymousAccount)
                    }
                }
            }

            if let account = model.publicAccount {
                Section(header: Text("Public account")) {
                    accountButton(account)
                }
            }
        }
    }

    func accountButton(_ account: Account) -> some View {
        Button {
            presentationMode.wrappedValue.dismiss()
            AccountsModel.shared.setCurrent(account)
        } label: {
            HStack {
                instanceImage(account.instance)

                if !account.anonymous {
                    Text(account.description)
                }

                Text((account.anonymous ? "" : "@ ") + account.urlHost)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundColor(account.anonymous ? .primary : .secondary)

                Spacer()

                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
                    .opacity(account == model.currentAccount ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(tvOS)
            .padding(.horizontal, 50)
        #endif
    }

    var closeButton: some View {
        Button(action: { presentationMode.wrappedValue.dismiss() }) {
            Label("Done", systemImage: "xmark")
        }
        #if os(macOS)
        .labelStyle(.titleOnly)
        #endif
        #if !os(tvOS)
        .keyboardShortcut(.cancelAction)
        #endif
    }

    func instanceImage(_ instance: Instance) -> some View {
        Image(instance.app.rawValue.capitalized)
            .resizable()
            .frame(width: 30, height: 30)
    }
}

struct AccountsView_Previews: PreviewProvider {
    static var previews: some View {
        AccountsView()
    }
}
