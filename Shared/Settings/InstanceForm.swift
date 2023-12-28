import SwiftUI

struct InstanceForm: View {
    @Binding var savedInstanceID: Instance.ID?

    @State private var name = ""
    @State private var url = ""
    @State private var isHTTPS = true

    @State private var temporaryIgnoreCertificateError = false
    @State private var ignoreCertificateError = false
    @State private var showAlert = false

    @State private var app: VideosApp?
    @State private var isValid = false
    @State private var isValidated = false
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var validationDebounce = Debounce()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.presentationMode) private var presentationMode

    @ObservedObject private var accounts = AccountsModel.shared

    var body: some View {
        VStack(alignment: .leading) {
            Group {
                header
                form
                #if os(macOS)
                    VStack {
                        validationStatus
                    }
                    .frame(alignment: .topLeading)
                    .padding(.horizontal, 15)
                #endif
                footer
            }
            .frame(maxWidth: 1000)
        }
        .onChange(of: url) { _ in validate() }
        .onChange(of: ignoreCertificateError) { _ in validate() }
        #if os(iOS)
            .padding(.vertical)
        #elseif os(tvOS)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .background(Color.background(scheme: colorScheme))
        #else
            .frame(width: 400)
            .padding(.vertical)
        #endif
    }

    private var header: some View {
        HStack {
            Text("Add Location")
                .font(.title2.bold())
            #if !os(macOS)
                Spacer()

                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
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
            TextField("Name", text: $name)

            TextField("Address", text: Binding<String>(
                get: { url },
                set: {
                    let regexPattern = "(http://|https://)[\\s]*(http://|https://)"
                    let regex = try? NSRegularExpression(pattern: regexPattern, options: [])

                    var cleanedURL: String = $0
                    var previousURL: String
                    repeat {
                        previousURL = cleanedURL
                        let range = NSRange(location: 0, length: cleanedURL.utf16.count)
                        cleanedURL = regex?.stringByReplacingMatches(in: cleanedURL, options: [], range: range, withTemplate: "$2") ?? cleanedURL
                    } while cleanedURL != previousURL

                    if cleanedURL.hasPrefix("http://") {
                        isHTTPS = false
                        url = cleanedURL
                    } else if cleanedURL.hasPrefix("https://") {
                        isHTTPS = true
                        url = cleanedURL
                    } else {
                        url = "\(isHTTPS ? "https://" : "http://")\(cleanedURL)"
                    }
                }
            ))

            #if !os(macOS)
            .autocapitalization(.none)
            .autocorrectionDisabled(/*@START_MENU_TOKEN@*/true/*@END_MENU_TOKEN@*/)
            .keyboardType(.URL)
            #endif

            Picker("Scheme", selection: $isHTTPS) {
                Text("http://").tag(false)
                Text("https://").tag(true)
            }
            .onChange(of: isHTTPS) { selectedIsHTTPS in
                if url.hasPrefix("http://"), selectedIsHTTPS {
                    url = url.replacingOccurrences(of: "http://", with: "https://")
                } else if url.hasPrefix("https://"), !selectedIsHTTPS {
                    url = url.replacingOccurrences(of: "https://", with: "http://")
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            Toggle("Ignore certificate errors", isOn: $temporaryIgnoreCertificateError)
                .onChange(of: temporaryIgnoreCertificateError) { newValue in
                    if newValue {
                        showAlert = true
                    } else {
                        // If the toggle is set to false, change the value directly
                        ignoreCertificateError = false
                    }
                }
                .alert(isPresented: $showAlert) {
                    Alert(
                        title: Text("Security Risk".uppercased()),
                        message: Text("Proceeding will ignore the SSL Certificate verification in your connection. This can pose a significant security threat, potentially exposing data to middlemen attacks.\n\nIgnoring Certificate errors should ONLY be used when dealing with known, self-signed certificates, such as those found in some test environments. In all other scenarios, it's recommended to resolve certificate errors rather than ignoring them.\n\nAre you absolutely sure you want to continue?"),
                        primaryButton: .default(Text("Yes")) {
                            ignoreCertificateError = temporaryIgnoreCertificateError
                        },
                        secondaryButton: .destructive(Text("No")) {
                            temporaryIgnoreCertificateError = ignoreCertificateError
                        }
                    )
                }

            #if os(tvOS)
                VStack {
                    validationStatus
                }
                .frame(minHeight: 100)
            #elseif os(iOS)
                validationStatus
            #endif
        }
    }

    @ViewBuilder var validationStatus: some View {
        Section {
            if url.isEmpty || url == "http://" || url == "https://" {
                Text("Enter location address to connect...")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.secondary)
            } else {
                AccountValidationStatus(
                    app: $app,
                    isValid: $isValid,
                    isValidated: $isValidated,
                    isValidating: $isValidating,
                    error: $validationError
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()

            #if os(macOS)
                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            #endif

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
            error: $validationError,
            ignoreCertificateError: $ignoreCertificateError
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

    func submitForm() {
        guard isValid, let app else {
            return
        }

        let savedInstance = InstancesModel.shared.add(app: app, name: name, url: url)
        savedInstanceID = savedInstance.id

        if accounts.isEmpty {
            accounts.setCurrent(savedInstance.anonymousAccount)
        }

        presentationMode.wrappedValue.dismiss()
    }
}

struct InstanceFormView_Previews: PreviewProvider {
    static var previews: some View {
        InstanceForm(savedInstanceID: .constant(nil))
    }
}
