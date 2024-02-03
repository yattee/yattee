import SwiftUI

struct ExportSettings: View {
    @ObservedObject private var model = ImportExportSettingsModel.shared
    @State private var presentingShareSheet = false
    @StateObject private var settings = SettingsModel.shared

    private var filesToShare = [ImportExportSettingsModel.exportFile]
    @ObservedObject private var navigation = NavigationModel.shared

    var body: some View {
        Group {
            #if os(macOS)
                VStack {
                    list

                    importExportButtons
                }
            #else
                list
                #if os(iOS)
                .listStyle(.insetGrouped)
                .sheet(
                    isPresented: $presentingShareSheet,
                    onDismiss: { self.model.isExportInProgress = false }
                ) {
                    ShareSheet(activityItems: filesToShare)
                        .id("settings-share-\(filesToShare.count)")
                }
                #endif
            #endif
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                exportButton
            }
        }
        #endif
        .navigationTitle("Export Settings")
    }

    var list: some View {
        List {
            exportView
        }
        .onAppear {
            model.reset()
        }
    }

    var importExportButtons: some View {
        HStack {
            importButton

            Spacer()

            exportButton
        }
    }

    @ViewBuilder var importButton: some View {
        #if os(macOS)
            Button {
                navigation.presentingSettingsFileImporter = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
        #endif
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
                        .opacity(isGroupInSelectedGroups ? 1 : 0)
                }
                .animation(nil, value: isGroupInSelectedGroups)
                .contentShape(Rectangle())
            }
        }

        var isGroupInSelectedGroups: Bool {
            model.selectedExportGroups.contains(group)
        }
    }

    var exportView: some View {
        Group {
            Section(header: Text("Settings")) {
                ForEach(ImportExportSettingsModel.ExportGroup.settingsGroups) { group in
                    ExportGroupRow(group: group)
                }
            }

            Section(header: Text("Locations")) {
                ForEach(ImportExportSettingsModel.ExportGroup.locationsGroups) { group in
                    ExportGroupRow(group: group)
                        .disabled(!model.isGroupEnabled(group))
                }
            }

            Section(header: Text("Other"), footer: otherGroupsFooter) {
                ForEach(ImportExportSettingsModel.ExportGroup.otherGroups) { group in
                    ExportGroupRow(group: group)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isExportInProgress)
    }

    var exportButton: some View {
        Button(action: exportSettings) {
            Text(model.isExportInProgress ? "In progress..." : "Export")
                .animation(nil, value: model.isExportInProgress)
            #if !os(macOS)
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            #endif
        }
        .disabled(!model.isExportAvailable)
    }

    @ViewBuilder var otherGroupsFooter: some View {
        Text("Other data include last used playback preferences and listing options")
    }

    func exportSettings() {
        let export = {
            model.isExportInProgress = true
            Delay.by(0.3) {
                model.exportAction()
                #if !os(macOS)
                    self.presentingShareSheet = true
                #endif
            }
        }

        if model.isGroupSelected(.accountsUnencryptedPasswords) {
            settings.presentAlert(Alert(
                title: Text("Are you sure you want to export unencrypted passwords?"),
                message: Text("Do not share this file with anyone or you can lose access to your accounts. If you don't select to export passwords you will be asked to provide them during import"),
                primaryButton: .destructive(Text("Export"), action: export),
                secondaryButton: .cancel()
            ))
        } else {
            export()
        }
    }
}

struct ExportSettings_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ExportSettings()
        }
    }
}
