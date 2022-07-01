import Foundation
import SwiftUI

struct AccountValidationStatus: View {
    @Binding var app: VideosApp?
    @Binding var isValid: Bool
    @Binding var isValidated: Bool
    @Binding var isValidating: Bool
    @Binding var error: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: validationStatusSystemImage)
                .foregroundColor(validationStatusColor)

                .frame(minWidth: 35, minHeight: 35)
                .opacity(isValidating ? 1 : (isValidated ? 1 : 0))

            VStack(alignment: .leading) {
                Text(isValid ? "Connected successfully (\(app?.name ?? "Unknown"))" : "Connection failed")
                if let error = error, !isValid {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .truncationMode(.tail)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 35)
            .opacity(isValidating ? 0 : (isValidated ? 1 : 0))
        }
    }

    var validationStatusSystemImage: String {
        if isValidating {
            return "bolt.horizontal.fill"
        } else {
            return isValid ? "checkmark.circle.fill" : "xmark.circle.fill"
        }
    }

    var validationStatusColor: Color {
        if isValidating {
            return .accentColor
        } else {
            return isValid ? .green : .red
        }
    }
}
