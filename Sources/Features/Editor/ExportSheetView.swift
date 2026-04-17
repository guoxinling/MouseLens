import AppKit
import SwiftUI

struct ExportSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let exportURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Export complete")
                .font(.title2.bold())
            Text("MouseLens rendered a polished MP4 from the recorded source with the current camera motion and styling.")
                .foregroundStyle(AppTheme.mutedText)

            if let exportURL {
                Text(exportURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.panelBorder.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            HStack(spacing: 12) {
                Button("Show in Finder") {
                    guard let exportURL else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([exportURL])
                }
                .buttonStyle(.borderedProminent)
                .disabled(exportURL == nil)

                Button("Preview Video") {
                    guard let exportURL else { return }
                    NSWorkspace.shared.open(exportURL)
                }
                .buttonStyle(.bordered)
                .disabled(exportURL == nil)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(28)
    }
}
