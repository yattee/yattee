import Defaults
import SwiftUI

struct FormatState: Equatable {
    let format: QualityProfile.Format
    var isActive: Bool
}

struct QualityProfileForm: View {
    @Binding var qualityProfileID: QualityProfile.ID?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.navigationStyle) private var navigationStyle

    @State private var valid = false

    @State private var initialized = false
    @State private var name = ""
    @State private var backend = PlayerBackendType.mpv
    @State private var resolution = ResolutionSetting.hd1080p60
    @State private var formats = [QualityProfile.Format]()
    @State private var orderedFormats: [FormatState] = []

    @Default(.qualityProfiles) private var qualityProfiles

    var qualityProfile: QualityProfile! {
        if let id = qualityProfileID {
            return QualityProfilesModel.shared.find(id)
        }

        return nil
    }

    // swiftlint:disable trailing_closure
    var body: some View {
        VStack {
            Group {
                header
                form
                footer
            }
            .frame(maxWidth: 1000)
        }
        #if os(tvOS)
        .padding(20)
        #endif

        .onAppear(perform: initializeForm)
        .onChange(of: backend, perform: { _ in backendChanged(self.backend); updateActiveFormats(); validate() })
        .onChange(of: name, perform: { _ in validate() })
        .onChange(of: resolution, perform: { _ in validate() })
        .onChange(of: orderedFormats, perform: { _ in validate() })
        #if os(iOS)
            .padding(.vertical)
        #elseif os(tvOS)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .background(Color.background(scheme: colorScheme))
        #else
            .frame(width: 400, height: 450)
            .padding(.vertical, 10)
        #endif
    }

    // swiftlint:enable trailing_closure

    var header: some View {
        HStack {
            Text(editing ? "Edit Quality Profile" : "Add Quality Profile")
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

    var form: some View {
        #if os(tvOS)
            ScrollView {
                VStack {
                    formFields
                }
                .padding(.horizontal, 20)
            }
        #else
            Form {
                formFields
                #if os(macOS)
                .padding(.horizontal)
                #endif
            }
        #endif
    }

    var formFields: some View {
        Group {
            Section {
                HStack {
                    nameHeader
                    TextField("Name", text: $name, onCommit: validate)
                        .labelsHidden()
                }
                #if os(tvOS)
                    Section(header: Text("Resolution")) {
                        qualityButton
                    }
                    Section(header: Text("Backend")) {
                        backendPicker
                    }
                #else
                    backendPicker
                    qualityPicker
                #endif
            }
            Section(header: Text("Preferred Formats"), footer: formatsFooter) {
                formatsPicker
            }
        }
        #if os(tvOS)
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    @ViewBuilder var nameHeader: some View {
        #if os(macOS)
            Text("Name")
        #endif
    }

    var formatsFooter: some View {
        VStack(alignment: .leading) {
            if #available(iOS 16.0, *) {
                Text("Formats can be reordered and will be selected in this order.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if #available(iOS 14.0, *) {
                Text("Formats will be selected in the order they are listed.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Formats will be selected in the order they are listed.")
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("**Note:** HLS is an adaptive format where specific resolution settings don't apply.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top)
            Text("Yattee attempts to match the quality that is closest to the set resolution, but exact results cannot be guaranteed.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 0.1)
        }
        .padding(.top, 2)
    }

    @ViewBuilder var qualityPicker: some View {
        let picker = Picker("Resolution", selection: $resolution) {
            ForEach(availableResolutions, id: \.self) { resolution in
                Text(resolution.description).tag(resolution)
            }
        }
        .modifier(SettingsPickerModifier())

        #if os(iOS)
            HStack {
                Text("Resolution")
                Spacer()
                Menu {
                    picker
                } label: {
                    Text(resolution.description)
                        .frame(minWidth: 120, alignment: .trailing)
                }
                .transaction { t in t.animation = .none }
            }

        #else
            picker
        #endif
    }

    #if os(tvOS)
        var qualityButton: some View {
            Button(resolution.description) {
                resolution = resolution.next()
            }
            .contextMenu {
                ForEach(availableResolutions, id: \.self) { resolution in
                    Button(resolution.description) {
                        self.resolution = resolution
                    }
                }
            }
        }
    #endif

    var availableResolutions: [ResolutionSetting] {
        ResolutionSetting.allCases.filter { !isResolutionDisabled($0) }
    }

    @ViewBuilder var backendPicker: some View {
        let picker = Picker("Backend", selection: $backend) {
            ForEach(PlayerBackendType.allCases, id: \.self) { backend in
                Text(backend.label).tag(backend)
            }
        }
        .modifier(SettingsPickerModifier())
        #if os(iOS)
            HStack {
                Text("Backend")
                Spacer()
                Menu {
                    picker
                } label: {
                    Text(backend.label)
                        .frame(minWidth: 120, alignment: .trailing)
                }
                .transaction { t in t.animation = .none }
            }

        #else
            picker
        #endif
    }

    var filteredFormatList: some View {
        ForEach(Array(orderedFormats.enumerated()), id: \.element.format) { idx, element in
            let format = element.format
            MultiselectRow(
                title: format.description,
                selected: element.isActive
            ) { value in
                orderedFormats[idx].isActive = value
            }
        }
        .onMove { source, destination in
            orderedFormats.move(fromOffsets: source, toOffset: destination)
            validate()
        }
    }

    @ViewBuilder var formatsPicker: some View {
        #if os(macOS)
            let list = filteredFormatList

            Group {
                if #available(macOS 12.0, *) {
                    list
                        .listStyle(.inset(alternatesRowBackgrounds: true))
                } else {
                    list
                        .listStyle(.inset)
                }
            }
            Spacer()
        #else
            filteredFormatList
        #endif
    }

    func isFormatSelected(_ format: QualityProfile.Format) -> Bool {
        return orderedFormats.first { $0.format == format }?.isActive ?? false
    }

    func toggleFormat(_ format: QualityProfile.Format, value: Bool) {
        if let index = orderedFormats.firstIndex(where: { $0.format == format }) {
            orderedFormats[index].isActive = value
        }
        validate() // Check validity after a toggle operation
    }

    var footer: some View {
        HStack {
            Spacer()
            Button("Save", action: submitForm)
                .disabled(!valid)
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

    var editing: Bool {
        !qualityProfile.isNil
    }

    func isFormatDisabled(_ format: QualityProfile.Format) -> Bool {
        guard backend == .appleAVPlayer else { return false }

        let avPlayerFormats = [.stream, QualityProfile.Format.hls]

        return !avPlayerFormats.contains(format)
    }

    func updateActiveFormats() {
        for (index, format) in orderedFormats.enumerated() where isFormatDisabled(format.format) {
            orderedFormats[index].isActive = false
        }
    }

    func isResolutionDisabled(_ resolution: ResolutionSetting) -> Bool {
        guard backend == .appleAVPlayer else { return false }

        let hd720p30 = Stream.Resolution.predefined(.hd720p30)

        return resolution.value > hd720p30
    }

    func initializeForm() {
        if editing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.name = qualityProfile.name ?? ""
                self.backend = qualityProfile.backend
                self.resolution = qualityProfile.resolution
                self.orderedFormats = qualityProfile.order.map { order in
                    let format = QualityProfile.Format.allCases[order]
                    let isActive = qualityProfile.formats.contains(format)
                    return FormatState(format: format, isActive: isActive)
                }
                self.initialized = true
            }
        } else {
            name = ""
            backend = .mpv
            resolution = .hd720p60
            orderedFormats = QualityProfile.Format.allCases.map {
                FormatState(format: $0, isActive: true)
            }
            initialized = true
        }
        validate()
    }

    func backendChanged(_: PlayerBackendType) {
        let defaultFormats = QualityProfile.Format.allCases.map {
            FormatState(format: $0, isActive: true)
        }

        if backend == .appleAVPlayer {
            orderedFormats = orderedFormats.filter { !isFormatDisabled($0.format) }
        } else {
            orderedFormats = defaultFormats
        }

        if isResolutionDisabled(resolution),
           let newResolution = availableResolutions.first
        {
            resolution = newResolution
        }
    }

    func validate() {
        if !initialized {
            valid = false
        } else if editing {
            let savedOrderFormats = qualityProfile.order.map { order in
                let format = QualityProfile.Format.allCases[order]
                let isActive = qualityProfile.formats.contains(format)
                return FormatState(format: format, isActive: isActive)
            }
            valid = name != qualityProfile.name
                || backend != qualityProfile.backend
                || resolution != qualityProfile.resolution
                || orderedFormats != savedOrderFormats
        } else { valid = true }
    }

    func submitForm() {
        guard valid else { return }

        let activeFormats = orderedFormats.filter(\.isActive).map(\.format)

        let formProfile = QualityProfile(
            id: qualityProfile?.id ?? UUID().uuidString,
            name: name,
            backend: backend,
            resolution: resolution,
            formats: activeFormats,
            order: orderedFormats.map { QualityProfile.Format.allCases.firstIndex(of: $0.format)! }
        )

        if editing {
            QualityProfilesModel.shared.update(qualityProfile, formProfile)
        } else {
            let wasEmpty = qualityProfiles.isEmpty
            QualityProfilesModel.shared.add(formProfile)

            if wasEmpty {
                QualityProfilesModel.shared.applyToAll(formProfile)
            }
        }

        presentationMode.wrappedValue.dismiss()
    }
}

struct QualityProfileForm_Previews: PreviewProvider {
    static var previews: some View {
        QualityProfileForm(qualityProfileID: .constant(QualityProfile.defaultProfile.id))
            .environment(\.navigationStyle, .tab)
    }
}
