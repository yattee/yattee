import SwiftUI

struct QualityProfileForm: View {
    @Binding var qualityProfileID: QualityProfile.ID?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.navigationStyle) private var navigationStyle

    @State private var valid = false

    @State private var name = ""
    @State private var backend = PlayerBackendType.mpv
    @State private var resolution = ResolutionSetting.best
    @State private var formats = [QualityProfile.Format]()

    var qualityProfile: QualityProfile! {
        if let id = qualityProfileID {
            return QualityProfilesModel.shared.find(id)
        }

        return nil
    }

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
        .onChange(of: backend, perform: backendChanged)
        .onChange(of: formats) { _ in validate() }
        #if os(iOS)
            .padding(.vertical)
        #elseif os(tvOS)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .background(Color.background(scheme: colorScheme))
        #else
            .frame(width: 400, height: 400)
            .padding(.vertical, 10)
        #endif
    }

    var header: some View {
        HStack(alignment: .center) {
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
        Text("Formats will be selected in order as listed.\nHLS is an adaptive format (resolution setting does not apply).")
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder var qualityPicker: some View {
        let picker = Picker("Resolution", selection: $resolution) {
            ForEach(availableResolutions, id: \.self) { resolution in
                Text(resolution.description).tag(resolution)
            }
        }
        .modifier(SettingsPickerModifier())

        #if os(iOS)
            return HStack {
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
            return picker
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
            return HStack {
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
            return picker
        #endif
    }

    @ViewBuilder var formatsPicker: some View {
        #if os(macOS)
            let list = ForEach(QualityProfile.Format.allCases, id: \.self) { format in
                MultiselectRow(
                    title: format.description,
                    selected: isFormatSelected(format),
                    disabled: isFormatDisabled(format)
                ) { value in
                    toggleFormat(format, value: value)
                }
            }

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
            ForEach(QualityProfile.Format.allCases, id: \.self) { format in
                MultiselectRow(
                    title: format.description,
                    selected: isFormatSelected(format),
                    disabled: isFormatDisabled(format)
                ) { value in
                    toggleFormat(format, value: value)
                }
            }
        #endif
    }

    func isFormatSelected(_ format: QualityProfile.Format) -> Bool {
        (editing && formats.isEmpty ? qualityProfile.formats : formats).contains(format)
    }

    func toggleFormat(_ format: QualityProfile.Format, value: Bool) {
        if let index = formats.firstIndex(where: { $0 == format }), !value {
            formats.remove(at: index)
        } else if value {
            formats.append(format)
        }
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

        let avPlayerFormats = [QualityProfile.Format.hls, .stream]

        return !avPlayerFormats.contains(format)
    }

    func isResolutionDisabled(_ resolution: ResolutionSetting) -> Bool {
        guard backend == .appleAVPlayer else { return false }

        return resolution != .best && resolution.value.height > 720
    }

    func initializeForm() {
        guard editing else {
            validate()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.name = qualityProfile.name ?? ""
            self.backend = qualityProfile.backend
            self.resolution = qualityProfile.resolution
            self.formats = .init(qualityProfile.formats)
        }

        validate()
    }

    func backendChanged(_: PlayerBackendType) {
        formats.filter { isFormatDisabled($0) }.forEach { format in
            if let index = formats.firstIndex(where: { $0 == format }) {
                formats.remove(at: index)
            }
        }

        if let newResolution = availableResolutions.first {
            resolution = newResolution
        }
    }

    func validate() {
        valid = !formats.isEmpty
    }

    func submitForm() {
        guard valid else { return }

        formats = formats.unique()

        let formProfile = QualityProfile(
            id: qualityProfile?.id ?? UUID().uuidString,
            name: name,
            backend: backend,
            resolution: resolution,
            formats: Array(formats)
        )

        if editing {
            QualityProfilesModel.shared.update(qualityProfile, formProfile)
        } else {
            QualityProfilesModel.shared.add(formProfile)
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
