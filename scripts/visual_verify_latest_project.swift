import AppKit
import Foundation

@main
struct VisualVerifyLatestProject {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let projectURL = try projectMetadataURL(from: arguments.first)
        let outputDirectory = try outputDirectoryURL(for: projectURL)

        let data = try Data(contentsOf: projectURL)
        let decodedProject = try JSONDecoder().decode(RecordingProject.self, from: data)
        let project = projectWithOptionalSourceOverride(decodedProject, argument: arguments.dropFirst().first)
        let renderer = VideoRenderer()
        let preset = ExportPreset.defaultPreset(for: project.style.aspectRatio)
        let timestamps = verificationTimestamps(for: project)

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        print("Project: \(project.name)")
        print("Metadata: \(projectURL.path)")
        print("Duration: \(String(format: "%.2f", project.duration))s")
        print("Events: \(project.events.count)")
        print("Clicks: \(project.events.filter { $0.type == .click }.count)")
        print("Output: \(outputDirectory.path)")

        var renderedFrameCount = 0
        for (index, timestamp) in timestamps.enumerated() {
            do {
                guard let image = try await renderer.makePreviewImage(for: project, preset: preset, timestamp: timestamp) else {
                    continue
                }

                let filename = String(format: "%02d_%05.2fs.png", index + 1, timestamp)
                let url = outputDirectory.appendingPathComponent(filename)
                try savePNG(image, to: url)
                renderedFrameCount += 1
                print("Frame: \(url.path)")
            } catch {
                print("Frame failed at \(String(format: "%.2f", timestamp))s: \(error.localizedDescription)")
            }
        }

        guard renderedFrameCount > 0 else {
            throw NSError(
                domain: "MouseLensVisualVerify",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No preview frames could be decoded from this project source."]
            )
        }
    }

    private static func projectMetadataURL(from argument: String?) throws -> URL {
        if let argument {
            var url = URL(fileURLWithPath: (argument as NSString).expandingTildeInPath)
            if url.hasDirectoryPath || url.pathExtension != "json" {
                url.appendPathComponent("project.json")
            }
            return url
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = support.appendingPathComponent("MouseLens", isDirectory: true)
        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        guard let latest = try directories
            .filter({ FileManager.default.fileExists(atPath: $0.appendingPathComponent("project.json").path) })
            .max(by: { lhs, rhs in
                let lhsDate = try lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                let rhsDate = try rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                return lhsDate < rhsDate
            })
        else {
            throw NSError(
                domain: "MouseLensVisualVerify",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No MouseLens project metadata was found."]
            )
        }

        return latest.appendingPathComponent("project.json")
    }

    private static func outputDirectoryURL(for projectURL: URL) throws -> URL {
        let projectID = projectURL.deletingLastPathComponent().lastPathComponent
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("MouseLensVisualVerify", isDirectory: true)
        return root.appendingPathComponent(projectID, isDirectory: true)
    }

    private static func projectWithOptionalSourceOverride(
        _ project: RecordingProject,
        argument: String?
    ) -> RecordingProject {
        guard let argument else { return project }
        let sourceURL = URL(fileURLWithPath: (argument as NSString).expandingTildeInPath)
        return RecordingProject(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            duration: project.duration,
            sourceVideoURL: sourceURL,
            reconstructsCursor: project.reconstructsCursor,
            events: project.events,
            cameraKeyframes: project.cameraKeyframes,
            style: project.style,
            trimRange: project.trimRange,
            clipSegments: project.clipSegments,
            manualZoomSegments: project.manualZoomSegments,
            zoomTrackEdited: project.zoomTrackEdited
        )
    }

    private static func verificationTimestamps(for project: RecordingProject) -> [TimeInterval] {
        let trimRange = project.effectiveTrimRange
        let clickTimes = project.events
            .filter { $0.type == .click }
            .map(\.timestamp)

        var timestamps: [TimeInterval] = [
            trimRange.start + min(0.4, trimRange.duration * 0.15),
            trimRange.start + (trimRange.duration * 0.5)
        ]

        if let firstClick = clickTimes.first {
            timestamps.append(firstClick)
            timestamps.append(firstClick + 0.08)
            timestamps.append(firstClick + 0.18)
        }

        if let farClick = clickTimes.dropFirst().first {
            timestamps.append(max(farClick - 0.12, trimRange.start))
            timestamps.append(farClick + 0.10)
        }

        timestamps.append(trimRange.end - min(0.4, trimRange.duration * 0.15))

        return Array(Set(timestamps.map { $0.clamped(to: trimRange.start...trimRange.end) }))
            .sorted()
    }

    private static func savePNG(_ image: NSImage, to url: URL) throws {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "MouseLensVisualVerify",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to convert preview image to PNG."]
            )
        }

        try pngData.write(to: url, options: .atomic)
    }
}
