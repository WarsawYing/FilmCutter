import Foundation

// MARK: - Film Format Presets

enum RollPreset: String, CaseIterable, Codable {
    case auto = "Auto Detect"
    case _135 = "135 / 35mm (3:2)"
    case _135p = "135 / 35mm Portrait (2:3)"
    case _65x24 = "65×24mm (2.71:1)"
    case _645 = "645 / 6×4.5 (4:3)"
    case _66 = "6×6 (1:1)"
    case _67 = "6×7 (~5:4)"
    case _68 = "6×8 (4:3)"
    case _69 = "6×9 (3:2)"
    case _612 = "6×12 (2:1)"
    case _617 = "6×17 (2.83:1)"

    var aspectRatio: Double {
        switch self {
        case .auto: return 0
        case ._135: return 3.0 / 2.0
        case ._135p: return 2.0 / 3.0
        case ._65x24: return 65.0 / 24.0
        case ._645: return 4.0 / 3.0
        case ._66: return 1.0
        case ._67: return 7.0 / 6.0
        case ._68: return 8.0 / 6.0
        case ._69: return 9.0 / 6.0
        case ._612: return 12.0 / 6.0
        case ._617: return 17.0 / 6.0
        }
    }

    var identifier: String {
        switch self {
        case .auto: return "auto"
        case ._135: return "135"
        case ._135p: return "135p"
        case ._65x24: return "65x24"
        case ._645: return "645"
        case ._66: return "66"
        case ._67: return "67"
        case ._68: return "68"
        case ._69: return "69"
        case ._612: return "612"
        case ._617: return "617"
        }
    }
}

// MARK: - Detector Versions

enum DetectorMode: String, CaseIterable, Codable {
    case v2 = "V2 — Constrained"
    case classic = "Classic"

    var identifier: String {
        switch self {
        case .v2: return "v2"
        case .classic: return "classic"
        }
    }
}

// MARK: - Scan Plan (one per input file)

struct ScanPlan: Codable, Identifiable {
    let id: Int
    let filePath: String
    let originalName: String
    var detectedFrames: [FilmFrame]
    /// Immutable baseline from the most recent detector run.  Manual editing
    /// changes detectedFrames, never this array, so Reset and dirty-state
    /// tracking remain meaningful.
    var automaticFrames: [FilmFrame]
    var hasManualEdits: Bool
    var detectorMode: DetectorMode
    var rollPreset: RollPreset
    var frameCount: Int { detectedFrames.count }
    var imageWidth: Int
    var imageHeight: Int
    var bitDepth: Int
    var previewB64: String?
}

// MARK: - Frame Model

struct FilmFrame: Codable, Identifiable, Equatable {
    let index: Int
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    var id: Int { index }

    var aspectRatio: Double {
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }

    static func == (lhs: FilmFrame, rhs: FilmFrame) -> Bool {
        lhs.index == rhs.index && lhs.x == rhs.x && lhs.y == rhs.y && lhs.width == rhs.width && lhs.height == rhs.height
    }
}

// MARK: - Roll Metadata

struct RollMetadata: Codable, Equatable {
    var camera: String = ""
    var lens: String = ""
    var aperture: String = ""
    var filmStock: String = ""
    var pushPull: String = "None"
    var date: String = ""
    var scanner: String = ""
    var notes: String = ""

    static func == (lhs: RollMetadata, rhs: RollMetadata) -> Bool {
        lhs.camera == rhs.camera && lhs.lens == rhs.lens
            && lhs.aperture == rhs.aperture && lhs.filmStock == rhs.filmStock
            && lhs.pushPull == rhs.pushPull && lhs.date == rhs.date
            && lhs.scanner == rhs.scanner && lhs.notes == rhs.notes
    }
}

// MARK: - Aperture Presets

enum AperturePresets {
    static let all = ["Not Available",
        "f/1.0", "f/1.2", "f/1.4", "f/1.8", "f/2.0", "f/2.8",
        "f/3.5", "f/4.0", "f/5.6", "f/8.0", "f/11", "f/16", "f/22", "f/32"
    ]
}

// MARK: - Push/Pull Presets

enum PushPullPresets {
    static let all = ["None",
        "+½", "+1", "+1½", "+2", "+3",
        "-½", "-1", "-2"
    ]
}

// MARK: - Film Stock Presets (grouped)

struct FilmStockGroup: Identifiable {
    let id = UUID()
    let groupName: String
    let stocks: [String]
}

enum FilmStockPresets {
    static let groups: [FilmStockGroup] = [
        FilmStockGroup(groupName: "Color Negative — Kodak", stocks: [
            "Portra 160", "Portra 400", "Portra 800",
            "Ektar 100", "Gold 200", "UltraMax 400",
            "Pro Image 100", "ColorPlus 200"
        ]),
        FilmStockGroup(groupName: "Color Negative — Fuji", stocks: [
            "Superia 100", "Superia 200", "Superia 400",
            "Superia 800", "Superia 1600", "Pro 400H",
            "Pro 160NS", "Pro 160C", "Reala 100",
            "Venus 800", "Natura 1600"
        ]),
        FilmStockGroup(groupName: "Color Negative — Other", stocks: [
            "Cinestill 50D", "Cinestill 400D", "Cinestill 800T",
            "Lomography Color 100", "Lomography Color 400",
            "Lomography Color 800", "Lomography Metropolis",
            "LomoChrome Purple", "LomoChrome Turquoise"
        ]),
        FilmStockGroup(groupName: "Kodak Vision3", stocks: [
            "Vision3 50D (5203)", "Vision3 250D (5207)",
            "Vision3 200T (5213)", "Vision3 500T (5219)"
        ]),
        FilmStockGroup(groupName: "Fuji Cinema", stocks: [
            "Eterna 250D (8563)", "Eterna 400T (8573)",
            "Eterna 500T (8583)", "Eterna Vivid 160 (8543)",
            "Eterna Vivid 250D (8546)", "Eterna Vivid 500T (8556)",
            "F-64D (8522)", "F-125T (8532)", "F-250T (8552)"
        ]),
        FilmStockGroup(groupName: "B&W — Kodak", stocks: [
            "Tri-X 400", "T-Max 100", "T-Max 400", "T-Max 3200"
        ]),
        FilmStockGroup(groupName: "B&W — Ilford", stocks: [
            "HP5 Plus", "Delta 100", "Delta 400", "Delta 3200",
            "FP4 Plus", "Pan F Plus", "XP2 Super"
        ]),
        FilmStockGroup(groupName: "B&W — Other", stocks: [
            "Neopan 100 Acros II", "Neopan 400", "Neopan 1600",
            "Fomapan 100", "Fomapan 200", "Fomapan 400",
            "Rollei RPX 25", "Rollei RPX 100", "Rollei RPX 400",
            "Bergger Pancro 400", "Cinestill BWXX", "Shanghai GP3 100"
        ]),
        FilmStockGroup(groupName: "Slide (E-6)", stocks: [
            "Provia 100F", "Velvia 50", "Velvia 100", "Ektachrome E100"
        ])
    ]

    static var allStocks: [String] {
        groups.flatMap { $0.stocks }
    }
}

// MARK: - Scanner Presets

enum ScannerPresets {
    static let all = [
        "Hasselblad X1 (Flextight)", "Hasselblad X5 (Flextight)",
        "Noritsu LS-600", "Noritsu LS-1100", "Noritsu HS-1800",
        "Noritsu QSS-32/34 Series", "Noritsu S-1700/1800",
        "Fujifilm SP-3000 (Frontier)", "Fujifilm SP-2000 (Frontier)",
        "Fujifilm SP-500 (Frontier)",
        "Nikon Super Coolscan 5000 ED", "Nikon Super Coolscan 9000 ED",
        "Nikon Coolscan V ED",
        "Microtek ArtixScan 120tf (M1)", "Microtek ArtixScan F1",
        "Microtek ScanMaker i900",
        "Epson Perfection V600", "Epson Perfection V700",
        "Epson Perfection V800/V850",
        "Plustek OpticFilm 8200i", "Plustek OpticFilm 8200i SE",
        "Plustek OpticFilm 120", "Plustek OpticFilm 120 Pro",
        "Pacific Image PrimeFilm XA", "Pacific Image PrimeFilm XAs",
        "Reflecta RPS 10M", "Reflecta ProScan 10T",
        "Canon CanoScan 9000F",
        "Camera Scan (DSLR/Mirrorless + Macro)",
        "Not Available"
    ]
}

// MARK: - Camera/Lens Memory

enum CameraLensMemory {
    private static let camerasKey = "filmcutter.cameras"
    private static let lensesKey = "filmcutter.lenses"

    static func rememberedCameras() -> [String] {
        UserDefaults.standard.stringArray(forKey: camerasKey) ?? []
    }

    static func rememberedLenses() -> [String] {
        UserDefaults.standard.stringArray(forKey: lensesKey) ?? []
    }

    static func rememberCamera(_ name: String) {
        var list = rememberedCameras()
        list.removeAll { $0 == name }
        list.insert(name, at: 0)
        if list.count > 20 { list = Array(list.prefix(20)) }
        UserDefaults.standard.set(list, forKey: camerasKey)
    }

    static func rememberLens(_ name: String) {
        var list = rememberedLenses()
        list.removeAll { $0 == name }
        list.insert(name, at: 0)
        if list.count > 20 { list = Array(list.prefix(20)) }
        UserDefaults.standard.set(list, forKey: lensesKey)
    }
}

// MARK: - Processing Request

struct ProcessRequest: Codable {
    let command: String
    let file: String?
    let borderPx: Int?
    let invert: Bool?
    let outputDir: String?
    let batchName: String?
    let frames: [FilmFrame]?
    let files: [String]?
    let format: String?
    let detector: String?
    let combinedFrames: [[FilmFrame]]?
    let metadata: RollMetadata?

    enum CodingKeys: String, CodingKey {
        case command, file
        case borderPx = "border_px"
        case invert
        case outputDir = "output_dir"
        case batchName = "batch_name"
        case frames, files, format, detector, metadata
        case combinedFrames = "combined_frames"
    }
}

// MARK: - Processing Result

struct ProcessResult: Codable {
    let status: String
    let message: String?
    let files: [String]?
    let frameCount: Int?
    let errorCode: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        let msg = try container.decodeIfPresent(String.self, forKey: .message)
        let err = try? container.decodeIfPresent(String.self, forKey: .error)
        message = msg ?? err
        frameCount = try container.decodeIfPresent(Int.self, forKey: .frameCount)
        errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)

        if let topFiles = try? container.decodeIfPresent([String].self, forKey: .files) {
            files = topFiles
        } else if status == "complete" || status == "ok" {
            var flatFiles: [String] = []
            if let results = try? container.decode([FileResult].self, forKey: .results) {
                for fr in results {
                    for of in fr.outputFiles {
                        flatFiles.append(of.outputPath)
                    }
                }
            }
            files = flatFiles.isEmpty ? nil : flatFiles
        } else {
            files = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(files, forKey: .files)
        try container.encodeIfPresent(frameCount, forKey: .frameCount)
        try container.encodeIfPresent(errorCode, forKey: .errorCode)
    }

    private struct FileResult: Codable {
        let outputFiles: [OutputFile]
        enum CodingKeys: String, CodingKey {
            case outputFiles = "output_files"
        }
    }

    private struct OutputFile: Codable {
        let outputPath: String
        enum CodingKeys: String, CodingKey {
            case outputPath = "output_path"
        }
    }

    enum CodingKeys: String, CodingKey {
        case status, message, files, results, error, frameCount = "frame_count", errorCode = "error_code"
    }
}

// MARK: - Processing State

enum ProcessingState {
    case idle
    case loading(progress: Double, message: String)
    case plan(plans: [ScanPlan], currentIndex: Int)
    case action(plans: [ScanPlan], rollName: String, outputDir: String)
    case processing(progress: Double)
    case failed(String)
    case completed([String])

}
