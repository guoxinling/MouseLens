import XCTest
@testable import MouseLens

final class CaptionModelTests: XCTestCase {
    func testCaptionTrackFindsSegmentAtTimestamp() {
        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let track = CaptionTrack(
            segments: [
                CaptionSegment(id: firstID, start: 0.5, end: 2.0, text: "Hello"),
                CaptionSegment(id: secondID, start: 2.0, end: 4.5, text: "World")
            ]
        )

        XCTAssertEqual(track.segment(at: 0.5)?.id, firstID)
        XCTAssertEqual(track.segment(at: 1.9)?.id, firstID)
        XCTAssertEqual(track.segment(at: 2.0)?.id, secondID)
    }

    func testCaptionTrackReturnsNilOutsideSegments() {
        let track = CaptionTrack(
            segments: [
                CaptionSegment(start: 1.0, end: 2.0, text: "Only segment")
            ]
        )

        XCTAssertNil(track.segment(at: 0.99))
        XCTAssertNil(track.segment(at: 2.0))
        XCTAssertNil(track.segment(at: 3.0))
    }

    func testCaptionTrackFindsSegmentsOverlappingTrimRange() {
        let earlyID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let middleID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let lateID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let track = CaptionTrack(
            segments: [
                CaptionSegment(id: earlyID, start: 0.0, end: 0.8, text: "Before"),
                CaptionSegment(id: middleID, start: 0.8, end: 2.0, text: "Overlap"),
                CaptionSegment(id: lateID, start: 3.0, end: 4.0, text: "After")
            ]
        )

        XCTAssertEqual(
            track.segments(overlappingStart: 1.5, end: 3.2).map(\.id),
            [middleID, lateID]
        )
    }

    func testCaptionTrackCodableRoundTripPreservesSegmentsStyleAndEnabledState() throws {
        let segmentID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let track = CaptionTrack(
            isEnabled: true,
            localeIdentifier: "zh-Hans",
            segments: [
                CaptionSegment(id: segmentID, start: 0.2, end: 1.7, text: "你好 MouseLens")
            ],
            style: CaptionStyle(
                position: .bottom,
                fontScale: 1.15,
                textColorHex: "#FFFFFF",
                backgroundOpacity: 0.62
            )
        )

        let encoded = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(CaptionTrack.self, from: encoded)

        XCTAssertEqual(decoded, track)
    }

    func testProjectModelCanPersistOptionalCaptionTrack() throws {
        let track = CaptionTrack(
            isEnabled: true,
            localeIdentifier: "en-US",
            segments: [
                CaptionSegment(start: 0, end: 1.5, text: "Generated caption")
            ]
        )
        let project = RecordingProject(
            id: UUID(),
            name: "Captions",
            createdAt: Date(timeIntervalSince1970: 100),
            duration: 4,
            sourceVideoURL: nil,
            events: [],
            cameraKeyframes: [],
            style: ProjectStyle(
                aspectRatio: .landscape,
                background: .aurora,
                cornerRadius: 10,
                shadowRadius: 12,
                followStrength: 0.5,
                clickEmphasis: 0.5,
                padding: 0.04
            ),
            captionTrack: track
        )

        let encoded = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(RecordingProject.self, from: encoded)

        XCTAssertEqual(decoded.captionTrack, track)
    }

    func testLegacyProjectWithoutCaptionTrackDecodesSuccessfully() throws {
        let legacyJSON = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Legacy",
          "createdAt": 100,
          "duration": 4,
          "captureTarget": "screen",
          "reconstructsCursor": true,
          "events": [],
          "cameraKeyframes": [],
          "style": {
            "aspectRatio": "landscape",
            "background": "aurora",
            "cornerRadius": 10,
            "shadowRadius": 12,
            "followStrength": 0.5,
            "clickEmphasis": 0.5,
            "padding": 0.04
          },
          "trimRange": {
            "start": 0,
            "end": 4
          },
          "clipSegments": [
            {
              "start": 0,
              "end": 4
            }
          ],
          "manualZoomSegments": [],
          "zoomTrackEdited": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RecordingProject.self, from: legacyJSON)

        XCTAssertNil(decoded.captionTrack)
    }
}
