import SwiftUI

struct ImportSettingsSheetView: View {
    @Binding var settingsFile: URL?
    @StateObject private var model = ImportSettingsSheetViewModel.shared
    @StateObject private var importExportModel = ImportExportSettingsModel.shared
    @StateObject private var fileModel = ImportSettingsFileModel.shared

    @Environment(\.presentationMode) private var presentationMode

    @State private var presentingCompletedAlert = false

    private let accountsModel = AccountsModel.shared

    var body: some View {
        Group {
            #if os(macOS)
                list
                    .frame(width: 700, height: 800)
            #else
                NavigationView {
                    list
                }
            #endif
        }
        .onAppear {
            guard let settingsFile else { return }
            fileModel.loadData(settingsFile)
        }
        .onChange(of: settingsFile) { _ in
            guard let settingsFile else { return }
            fileModel.loadData(settingsFile)
        }
    }

    var list: some View {
        List {
            importGroupView

            importOptions

            metadata
        }
        .alert(isPresented: $presentingCompletedAlert) {
            completedAlert
        }
        #if os(iOS)
        .backport
        .scrollDismissesKeyboardInteractively()
        #endif
        .navigationTitle("Import Settings")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Text("Cancel")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: {
                    fileModel.performImport()
                    presentingCompletedAlert = true
                    ImportExportSettingsModel.shared.reset()
                }) {
                    Text("Import")
                }
                .disabled(!canImport)
            }
        }
    }

    var completedAlert: Alert {
        Alert(
            title: Text("Import Completed"),
            dismissButton: .default(Text("Close")) {
                if accountsModel.isEmpty,
                   let account = InstancesModel.shared.all.first?.anonymousAccount
                {
                    accountsModel.setCurrent(account)
                }
                presentationMode.wrappedValue.dismiss()
            }
        )
    }

    var canImport: Bool {
        return !model.selectedAccounts.isEmpty || !model.selectedInstances.isEmpty || !importExportModel.selectedExportGroups.isEmpty
    }

    var locationsSettingsGroupImporter: LocationsSettingsGroupImporter? {
        fileModel.locationsSettingsGroupImporter
    }

    struct ExportGroupRow: View {
        let group: ImportExportSettingsModel.ExportGroup

        @ObservedObject private var model = ImportExportSettingsModel.shared

        var body: some View {
            Button(action: { model.toggleExportGroupSelection(group) }) {
                HStack {
                    Text(group.label.localized())
                    Spacer()
                    Image(systemName: "checkmark")
                        .foregroundColor(.accentColor)
                        .opacity(isChecked ? 1 : 0)
                }
                .contentShape(Rectangle())
                .foregroundColor(.primary)
                .animation(nil, value: isChecked)
            }
            .buttonStyle(.plain)
        }

        var isChecked: Bool {
            model.selectedExportGroups.contains(group)
        }
    }

    var importGroupView: some View {
        Group {
            Section(header: Text("Settings")) {
                ForEach(ImportExportSettingsModel.ExportGroup.settingsGroups) { group in
                    ExportGroupRow(group: group)
                        .disabled(!fileModel.isGroupIncludedInFile(group))
                }
            }

            Section(header: Text("Other")) {
                ForEach(ImportExportSettingsModel.ExportGroup.otherGroups) { group in
                    ExportGroupRow(group: group)
                        .disabled(!fileModel.isGroupIncludedInFile(group))
                }
            }
        }
    }

    @ViewBuilder var metadata: some View {
        if let settingsFile {
            Section(header: Text("File information")) {
                MetadataRow(name: Text("Name"), value: Text(fileModel.filename(settingsFile)))

                if let date = fileModel.metadataDate {
                    MetadataRow(name: Text("Date"), value: Text(date))
                    #if os(tvOS)
                        .focusable()
                    #endif
                }

                if let build = fileModel.metadataBuild {
                    MetadataRow(name: Text("Build"), value: Text(build))
                    #if os(tvOS)
                        .focusable()
                    #endif
                }

                if let platform = fileModel.metadataPlatform {
                    MetadataRow(name: Text("Platform"), value: Text(platform))
                    #if os(tvOS)
                        .focusable()
                    #endif
                }
            }
        }
    }

    struct MetadataRow: View {
        let name: Text
        let value: Text

        var body: some View {
            HStack {
                name
                    .layoutPriority(2)

                Spacer()

                value
                    .layoutPriority(1)
                    .lineLimit(2)
                    .foregroundColor(.secondary)
            }
        }
    }

    var instances: [Instance] {
        locationsSettingsGroupImporter?.instances ?? []
    }

    var accounts: [Account] {
        locationsSettingsGroupImporter?.accounts ?? []
    }

    struct ImportInstanceRow: View {
        var instance: Instance
        var accounts: [Account]

        @ObservedObject private var model = ImportSettingsSheetViewModel.shared

        var body: some View {
            Button(action: { model.toggleInstance(instance, accounts: accounts) }) {
                VStack {
                    Group {
                        HStack {
                            Text(instance.description)
                            Spacer()
                            Image(systemName: "checkmark")
                                .opacity(isChecked ? 1 : 0)
                                .foregroundColor(.accentColor)
                        }

                        if model.isInstanceAlreadyAdded(instance) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("Custom Location already exists")
                            }
                            .font(.caption)
                            .padding(.vertical, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .foregroundColor(.primary)
                .transaction { t in t.animation = nil }
            }
            .buttonStyle(.plain)
        }

        var isChecked: Bool {
            model.isImportable(instance) && model.selectedInstances.contains(instance.id)
        }
    }

    @ViewBuilder var importOptions: some View {
        if fileModel.isPublicInstancesSettingsGroupInFile || !instances.isEmpty {
            Section(header: Text("Locations")) {
                if fileModel.isPublicInstancesSettingsGroupInFile {
                    ExportGroupRow(group: .locationsSettings)
                }

                ForEach(instances) { instance in
                    ImportInstanceRow(instance: instance, accounts: accounts)
                }
            }
        }

        if !accounts.isEmpty {
            Section(header: Text("Accounts")) {
                ForEach(accounts) { account in
                    ImportSettingsAccountRow(account: account, fileModel: fileModel)
                }
            }
        }
    }
}

struct ImportSettingsSheetView_Previews: PreviewProvider {
    static var previews: some View {
        ImportSettingsSheetView(settingsFile: .constant(URL(string: "https://gist.githubusercontent.com/arekf/578668969c9fdef1b3828bea864c3956/raw/f794a95a20261bcb1145e656c8dda00bea339e2a/yattee-recents.yatteesettings")!))
    }
}
