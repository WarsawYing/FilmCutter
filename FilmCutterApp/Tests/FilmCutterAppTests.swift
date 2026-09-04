import XCTest
@testable import FilmCutterApp

@MainActor
final class FilmCutterAppTests: XCTestCase {
    func testPublishedLocalesContainEveryEnglishKey() {
        let tables = LocalizationStore.tables
        let english = Set(tables["en"]?.keys ?? Dictionary<String, String>().keys)
        XCTAssertFalse(english.isEmpty)
        for identifier in ["zh-Hans", "ja", "es", "fr"] {
            XCTAssertEqual(Set(tables[identifier]?.keys ?? Dictionary<String, String>().keys), english)
        }
    }

    func testLanguagesProvideLocalizedPluralForms() {
        let store = LocalizationStore()
        store.language = .en
        XCTAssertEqual(store.plural("found.frames", count: 1), "Found 1 frame")
        XCTAssertEqual(store.plural("found.frames", count: 2), "Found 2 frames")
        store.language = .fr
        XCTAssertEqual(store.plural("found.frames", count: 1), "1 vue détectée")
        XCTAssertEqual(store.plural("found.frames", count: 2), "2 vues détectées")
    }

    func testSystemLanguageResolutionAndFallback() {
        XCTAssertEqual(AppLanguage.resolvedIdentifier(for: "zh-Hans-CN"), "zh-Hans")
        XCTAssertEqual(AppLanguage.resolvedIdentifier(for: "ja-JP"), "ja")
        XCTAssertEqual(AppLanguage.resolvedIdentifier(for: "es-MX"), "es")
        XCTAssertEqual(AppLanguage.resolvedIdentifier(for: "fr-CA"), "fr")
        XCTAssertEqual(AppLanguage.resolvedIdentifier(for: "de-DE"), "en")
    }

    func testLanguageSelectionPersists() {
        let defaults = UserDefaults.standard
        let key = "filmcutter.language"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.set("fr", forKey: key)
        let store = LocalizationStore()
        XCTAssertEqual(store.language, .fr)
        store.language = .ja
        XCTAssertEqual(defaults.string(forKey: key), "ja")
    }

    func testFilmFormatUsesStableIdentifiers() {
        XCTAssertEqual(RollPreset._135.identifier, "135")
        XCTAssertEqual(RollPreset._135Half.identifier, "135_half")
        XCTAssertEqual(RollPreset.from(identifier: "135p"), ._135)
        XCTAssertEqual(RollPreset.allCases.count, 11)
    }

    func testUnicodeNamingMatchesRuntimeContract() {
        XCTAssertEqual(OutputNaming.sanitizedBaseName("  胶卷 / 夏天._ "), "胶卷 - 夏天")
        XCTAssertEqual(OutputNaming.filename(base: "胶卷 / 夏天", index: 2), "胶卷 - 夏天_002.tif")
        XCTAssertEqual(OutputNaming.sanitizedBaseName("../"), "")
    }

    func testManualEditStateIsPerScan() {
        let frame = FilmFrame(index: 0, x: 0, y: 0, width: 10, height: 10)
        let first = ScanPlan(
            id: 0, filePath: "/a.tif", originalName: "a.tif",
            detectedFrames: [frame], automaticFrames: [frame], hasManualEdits: false,
            rollPreset: .auto, expectedFrameCount: nil, useContourRefinement: false,
            refinementApplied: false, refinementFallbackReason: nil, detectionRevision: 0,
            imageWidth: 100, imageHeight: 100, bitDepth: 16, previewB64: nil)
        var second = first
        second.detectedFrames = []
        second.hasManualEdits = true
        XCTAssertFalse(first.hasManualEdits)
        XCTAssertTrue(second.hasManualEdits)
    }

    func testProcessRequestCarriesSelectedBorder() throws {
        let request = ProcessRequest(
            command: "process", file: nil, borderPx: 7, invert: false,
            outputDir: "/tmp/output", batchName: "Roll", frames: nil,
            files: ["/tmp/input.tif"], formatID: nil, expectedCount: nil,
            refineContour: nil, frameCount: nil, combinedFrames: [[]], metadata: nil)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(object?["border_px"] as? Int, 7)
    }

    func testNaturalInputOrdering() {
        let urls = ["scan10.tif", "scan2.tif", "scan1.tif"].map {
            URL(fileURLWithPath: "/input/\($0)")
        }
        XCTAssertEqual(InputOrdering.naturalSort(urls).map(\.lastPathComponent),
                       ["scan1.tif", "scan2.tif", "scan10.tif"])
    }

    func testPreviewLayoutAlwaysFitsInsideCanvas() {
        for source in [(12_000, 400), (400, 12_000), (8_000, 8_000)] {
            let layout = FrameEditorLogic.previewLayout(
                container: CGSize(width: 640, height: 420),
                imageWidth: source.0,
                imageHeight: source.1
            )
            XCTAssertGreaterThan(layout.scale, 0)
            XCTAssertGreaterThanOrEqual(layout.origin.x, 17.99)
            XCTAssertGreaterThanOrEqual(layout.origin.y, 17.99)
            XCTAssertLessThanOrEqual(layout.origin.x + layout.imageSize.width, 622.01)
            XCTAssertLessThanOrEqual(layout.origin.y + layout.imageSize.height, 402.01)
        }
    }

    func testMoveAndResizeClampToImageAndPreserveIdentity() {
        let id = UUID()
        let frame = FilmFrame(id: id, index: 3, x: 20, y: 20, width: 100, height: 80)
        let moved = FrameEditorLogic.moved(
            frame, deltaX: 500, deltaY: -500, imageWidth: 300, imageHeight: 200
        )
        XCTAssertEqual(moved.id, id)
        XCTAssertEqual(moved.x, 200)
        XCTAssertEqual(moved.y, 0)

        let resized = FrameEditorLogic.resizedFromBottomRight(
            moved, deltaWidth: 500, deltaHeight: 500, imageWidth: 300, imageHeight: 200
        )
        XCTAssertEqual(resized.id, id)
        XCTAssertEqual(resized.width, 100)
        XCTAssertEqual(resized.height, 200)
    }

    func testNormalizationAndExplicitOrderingPreserveFrameIdentity() {
        let right = FilmFrame(index: 9, x: 300, y: 20, width: 100, height: 80)
        let left = FilmFrame(index: 4, x: 20, y: 20, width: 100, height: 80)
        let ordered = FrameEditorLogic.spatiallyOrdered([right, left])
        XCTAssertEqual(ordered.map(\.id), [left.id, right.id])
        XCTAssertEqual(ordered.map(\.index), [0, 1])
    }

    func testGeometryValidationFindsNearDuplicateFrames() {
        let first = FilmFrame(index: 0, x: 10, y: 10, width: 100, height: 100)
        let second = FilmFrame(index: 1, x: 15, y: 15, width: 100, height: 100)
        XCTAssertEqual(
            FrameEditorLogic.issues(in: [first, second], imageWidth: 500, imageHeight: 500),
            [.nearDuplicate(first.id, second.id)]
        )
    }

    func testFrameWireFormatDoesNotExposeSwiftUIIdentity() throws {
        let frame = FilmFrame(index: 2, x: 1, y: 2, width: 30, height: 40)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as? [String: Any]
        XCTAssertNil(object?["id"])
        XCTAssertEqual(object?["index"] as? Int, 2)
        let decoded = try JSONDecoder().decode(FilmFrame.self, from: JSONEncoder().encode(frame))
        XCTAssertNotEqual(decoded.id, frame.id)
        XCTAssertEqual(decoded, frame)
    }

    func testBridgeRestoresTheLastEditablePlan() {
        let frame = FilmFrame(index: 0, x: 0, y: 0, width: 10, height: 10)
        let plan = ScanPlan(
            id: 0, filePath: "/a.tif", originalName: "a.tif",
            detectedFrames: [frame], automaticFrames: [frame], hasManualEdits: true,
            rollPreset: ._135, expectedFrameCount: 1, useContourRefinement: false,
            refinementApplied: false, refinementFallbackReason: nil, detectionRevision: 0,
            imageWidth: 100, imageHeight: 100, bitDepth: 16, previewB64: nil)
        let bridge = PythonBridge()
        bridge.transitionToPlan([plan], index: 0)
        bridge.transitionToAction(plans: [plan], rollName: "Roll", outputDir: "/output")
        bridge.restorePlanIfAvailable()
        guard case .plan(let restored, let index) = bridge.state else {
            return XCTFail("Expected editable plan state")
        }
        XCTAssertEqual(index, 0)
        XCTAssertTrue(restored[0].hasManualEdits)
        XCTAssertEqual(restored[0].rollPreset, ._135)
    }
}
