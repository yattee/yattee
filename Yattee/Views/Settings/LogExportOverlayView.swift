//
//  LogExportOverlayView.swift
//  Yattee
//
//  Overlay view for exporting logs via HTTP server on tvOS.
//

import SwiftUI

#if os(tvOS)
import CoreImage.CIFilterBuiltins

/// Overlay view displayed when exporting logs via HTTP server on tvOS.
/// Shows the URL, QR code, and countdown timer.
struct LogExportOverlayView: View {
    @Bindable var server: LogExportHTTPServer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 40) {
            Text(String(localized: "settings.advanced.logs.export.title"))
                .font(.title)
                .fontWeight(.bold)

            if let errorMessage = server.errorMessage {
                errorView(errorMessage)
            } else if server.isRunning, let url = server.serverURL {
                runningView(url: url)
            } else {
                startingView
            }

            Spacer()

            Button {
                server.stop()
                dismiss()
            } label: {
                Text(server.isRunning ? String(localized: "settings.advanced.logs.export.stop") : String(localized: "common.close"))
                    .frame(minWidth: 300)
            }
            .buttonStyle(.bordered)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            server.start()
        }
        .onDisappear {
            server.stop()
        }
    }

    // MARK: - Views

    private var startingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(2)

            Text(String(localized: "settings.advanced.logs.export.starting"))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private func runningView(url: String) -> some View {
        VStack(spacing: 30) {
            // Instructions
            Text(String(localized: "settings.advanced.logs.export.instructions"))
                .font(.title3)
                .foregroundStyle(.secondary)

            // Full URL on one line
            Text(url)
                .font(.system(size: 38, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)

            // QR Code below
            if let qrImage = generateQRCode(from: url) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 280, height: 280)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(String(localized: "settings.advanced.logs.export.scanQR"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Countdown timer
            Text(String(localized: "settings.advanced.logs.export.autoStop \(formattedTimeRemaining)"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var formattedTimeRemaining: String {
        let minutes = server.secondsRemaining / 60
        let seconds = server.secondsRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Generate a QR code image from a string.
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        guard let data = string.data(using: .ascii) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up the QR code (it's generated at a small size)
        let scale: CGFloat = 10
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
#endif
