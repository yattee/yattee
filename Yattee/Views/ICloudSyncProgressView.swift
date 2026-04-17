//
//  ICloudSyncProgressView.swift
//  Yattee
//
//  Blocking progress overlay shown during the first-launch iCloud sync.
//

import SwiftUI

struct ICloudSyncProgressView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    private var cloudKitSync: CloudKitSyncEngine? { appEnvironment?.cloudKitSync }

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)

            Text(String(localized: "onboarding.cloud.syncing.title"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(progressText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 260)
        #endif
        .interactiveDismissDisabled()
    }

    private var progressText: String {
        if let upload = cloudKitSync?.uploadProgress {
            return upload.displayText
        }
        return String(localized: "onboarding.cloud.syncing.preparing")
    }
}

#Preview {
    ICloudSyncProgressView()
        .appEnvironment(.preview)
}
