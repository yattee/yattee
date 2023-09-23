import Foundation
import SwiftUI

struct AccountValidationStatus: View {
    @Binding var app: VideosApp?
    @Binding var isValid: Bool
    @Binding var isValidated: Bool
    @Binding var isValidating: Bool
    @Binding var error: String?

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: validationStatusSystemImage)
                    .foregroundColor(validationStatusColor)
                    .imageScale(.medium)
                    .opacity(isValidating ? 1 : (isValidated ? 1 : 0))

                Text(isValid ? "Connected successfully (\(app?.name ?? "Unknown"))" : "Connection failed")
                    .opacity(isValidated && !isValidating ? 1 : 0)
            }
            if errorVisible {
                Text(error ?? "")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 5)
                    .opacity(errorTextVisible ? 1 : 0)
            }
        }
    }

    var errorVisible: Bool {
        #if !os(iOS)
            true
        #else
            errorTextVisible
        #endif
    }

    var errorTextVisible: Bool {
        error != nil && isValidated && !isValid && !isValidating
    }

    var validationStatusSystemImage: String {
        if isValidating {
            return "bolt.horizontal.fill"
        }

        return isValid ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    var validationStatusColor: Color {
        if isValidating {
            return .accentColor
        }

        return isValid ? .green : .red
    }
}
