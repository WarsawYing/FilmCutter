import Foundation
import Combine

/// Bridge between Swift and the Python processing engine.
final class PythonBridge: ObservableObject {
    // MARK: - Published State

    @Published private(set) var state: ProcessingState = .idle

    // MARK: - Private Properties

    private var enginePath: String = ""
    private var pythonPath: String = ""
    private let processQueue = DispatchQueue(label: "com.filmcutter.python", qos: .userInitiated)
    private var currentProcess: Process?
    private var recoverablePlan: ([ScanPlan], Int)?

    /// Maximum time (seconds) to wait for a Python command to complete
    private static let commandTimeout: TimeInterval = 360  // 6 min for large scans

    // MARK: - Initialization

    init() {
        let rawPath = Bundle.main.executableURL?.path ?? ProcessInfo.processInfo.arguments[0]
        let exeURL = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath()
        let exeDir = exeURL.deletingLastPathComponent()

        // 1. Check inside .app bundle Resources (next to MacOS folder)
        let resourcePath = exeDir.deletingLastPathComponent().appendingPathComponent("Resources")
        let bundledEngine = resourcePath.appendingPathComponent("PythonEngine/engine.py").path
        if FileManager.default.fileExists(atPath: bundledEngine) {
            enginePath = bundledEngine
            let bundledPython = resourcePath.appendingPathComponent("PythonRuntime/bin/python3").path
            if FileManager.default.isExecutableFile(atPath: bundledPython) {
                pythonPath = bundledPython
            }
        }

        #if DEBUG
        // Development builds may use an explicitly supplied interpreter.
        if enginePath.isEmpty {
            var dir: URL? = exeDir
            while let d = dir, d.path != "/" {
                let candidate = d.appendingPathComponent("PythonEngine/engine.py").path
                if FileManager.default.fileExists(atPath: candidate) {
                    enginePath = candidate
                    let venvPy = d.appendingPathComponent("PythonEngine/venv/bin/python3").path
                    if FileManager.default.isExecutableFile(atPath: venvPy) {
                        pythonPath = venvPy
                    } else if let executable = ProcessInfo.processInfo.environment["FILMCUTTER_DEV_PYTHON"],
                              FileManager.default.isExecutableFile(atPath: executable) {
                        pythonPath = executable
                    }
                    break
                }
                dir = d.deletingLastPathComponent()
            }
        }
        #endif

        #if DEBUG
        print("[PythonBridge] Python: \(pythonPath)\n[PythonBridge] Engine: \(enginePath)")
        #endif
    }

    deinit {
        killProcess()
    }

    // MARK: - Public API

    /// Detect frames and generate preview(s) for the given file(s).
    func loadScanPlans(files: [String], format: String = "auto",
                       expectedCount: Int? = nil, refineContour: Bool = false) {
        state = .loading(progress: 0.0, message: "PROGRESS_START")

        let request = ProcessRequest(
            command: "preview",
            file: files.first,
            borderPx: 0,
            invert: nil,
            outputDir: nil,
            batchName: nil,
            frames: nil,
            files: files,
            formatID: format,
            expectedCount: expectedCount,
            refineContour: refineContour,
            frameCount: nil,
            combinedFrames: nil,
            metadata: nil
        )

        runEngineStreaming(request: request) { [weak self] (result: Result<PreviewBulkResult, Error>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let response):
                    if response.status == "ok", let previewData = response.data {
                        let plans = previewData.enumerated().map { idx, pd -> ScanPlan? in
                            // A zero-frame detector result is still a usable
                            // plan: the preview opens and the user can add the
                            // missing rectangles manually.
                            guard let frames = pd.frames else { return nil }
                            return ScanPlan(
                                id: idx,
                                filePath: pd.filePath,
                                originalName: pd.fileName,
                                detectedFrames: frames,
                                automaticFrames: frames,
                                hasManualEdits: false,
                                rollPreset: RollPreset.from(identifier: pd.selectedFormat ?? format),
                                expectedFrameCount: pd.expectedCount,
                                useContourRefinement: refineContour,
                                refinementApplied: pd.refinementApplied ?? false,
                                refinementFallbackReason: pd.refinementFallbackReason,
                                detectionRevision: 0,
                                imageWidth: pd.width ?? 0,
                                imageHeight: pd.height ?? 0,
                                bitDepth: pd.bitDepth ?? 16,
                                previewB64: pd.previewB64
                            )
                        }.compactMap { $0 }
                        if plans.isEmpty {
                            self.state = .failed("ERR_NO_FRAMES")
                        } else {
                            self.state = .plan(plans: plans, currentIndex: 0)
                        }
                    } else {
                        self.state = .failed(response.errorCode ?? "ERR_PREVIEW_PARTIAL")
                    }
                case .failure(let error):
                    self.state = .failed((error as? ProcessError)?.code ?? "ERR_ENGINE")
                }
            }
        }
    }

    /// Start cutting all planned frames (entire batch).
    func cutAll(plans: [ScanPlan], rollName: String, outputDir: String,
                invert: Bool, borderPx: Int = 4, metadata: RollMetadata? = nil) {
        state = .processing(progress: 0.0)

        let combinedFrames = plans.map { $0.detectedFrames }

        let request = ProcessRequest(
            command: "process",
            file: nil,
            borderPx: borderPx,
            invert: invert,
            outputDir: outputDir,
            batchName: rollName,
            frames: nil,
            files: plans.map { $0.filePath },
            formatID: nil,
            expectedCount: nil,
            refineContour: nil,
            frameCount: nil,
            combinedFrames: combinedFrames,
            metadata: metadata
        )

        runEngineStreaming(request: request) { [weak self] (result: Result<ProcessResult, Error>) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let pr):
                    if pr.status == "ok" || pr.status == "complete" {
                        self.state = .completed(pr.files ?? [])
                    } else {
                        self.state = .failed(pr.errorCode ?? "ERR_PROCESS")
                    }
                case .failure(let error):
                    self.state = .failed((error as? ProcessError)?.code ?? "ERR_ENGINE")
                }
            }
        }
    }

    /// Update a single scan's detection with a specific format preset.
    func redetect(filePath: String, format: String, expectedCount: Int?,
                  refineContour: Bool,
                  completion: @escaping (Result<PreviewData, Error>) -> Void) {
        let request = ProcessRequest(
            command: "preview",
            file: filePath,
            borderPx: 0,
            invert: nil,
            outputDir: nil,
            batchName: nil,
            frames: nil,
            files: [filePath],
            formatID: format,
            expectedCount: expectedCount,
            refineContour: refineContour,
            frameCount: nil,
            combinedFrames: nil,
            metadata: nil
        )

        runEngineStreaming(request: request) { (result: Result<PreviewBulkResult, Error>) in
            switch result {
            case .success(let response):
                if response.status == "ok", let first = response.data?.first {
                    completion(.success(first))
                } else {
                    completion(.failure(NSError(domain: "FilmCutter", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: response.errorCode ?? "ERR_PREVIEW_PARTIAL"])))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Transition to plan state
    func transitionToPlan(_ plans: [ScanPlan], index: Int) {
        recoverablePlan = (plans, index)
        state = .plan(plans: plans, currentIndex: index)
    }

    /// Transition to action stage
    func transitionToAction(plans: [ScanPlan], rollName: String, outputDir: String) {
        recoverablePlan = (plans, 0)
        state = .action(plans: plans, rollName: rollName, outputDir: outputDir)
    }

    func restorePlanIfAvailable() {
        if let (plans, index) = recoverablePlan {
            state = .plan(plans: plans, currentIndex: min(index, max(0, plans.count - 1)))
        } else {
            state = .idle
        }
    }

    /// Reset back to idle.
    func reset() {
        killProcess()
        recoverablePlan = nil
        state = .idle
    }

    func cancelCurrentOperation() {
        killProcess()
    }

    // MARK: - Streaming Engine Communication

    /// Run a Python command with line-by-line streaming output.
    /// While the final response is collected, intermediate lines with
    /// `{"status":"progress",...}` update the UI in real time.
    private func runEngineStreaming<T: Codable>(
        request: ProcessRequest,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        processQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let outputData = try self.runPythonWithProgress(request: request)
                let decoder = JSONDecoder()
                let result = try decoder.decode(T.self, from: outputData)
                completion(.success(result))
            } catch let error as ProcessError {
                completion(.failure(error))
            } catch {
                completion(.failure(ProcessError(code: "ERR_0006",
                    message: "Decode error: \(error.localizedDescription)")))
            }
        }
    }

    /// Run the Python process, read line-by-line, publish progress, and return final JSON.
    /// Waits up to `commandTimeout` seconds, then kills the process.
    private func runPythonWithProgress(request: ProcessRequest) throws -> Data {
        let encoder = JSONEncoder()
        guard !enginePath.isEmpty, FileManager.default.fileExists(atPath: enginePath) else {
            throw ProcessError(code: "ERR_ENGINE", message: "engine_missing")
        }
        guard FileManager.default.isExecutableFile(atPath: pythonPath) else {
            throw ProcessError(code: "ERR_ENGINE", message: "runtime_missing")
        }
        let inputData = try encoder.encode(request)
        guard let inputString = String(data: inputData, encoding: .utf8) else {
            throw ProcessError(code: "ERR_0006", message: "Failed to encode request")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-B", "-I", enginePath]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.currentProcess = process
        defer {
            // Any early throw (launch, stdin, decoding preparation) must not
            // leave a Python child waiting forever in the background.
            if process.isRunning {
                self.terminateProcess(process)
            }
            // Do not let a completed Process remain the target of a later reset.
            if self.currentProcess === process {
                self.currentProcess = nil
            }
        }

        // Start the process
        try process.run()

        // Write input JSON
        stdinPipe.fileHandleForWriting.write(inputString.data(using: .utf8)!)
        stdinPipe.fileHandleForWriting.write("\n".data(using: .utf8)!)
        try stdinPipe.fileHandleForWriting.close()

        // Read output line by line from the file descriptor
        let fileHandle = stdoutPipe.fileHandleForReading
        let fileDescriptor = fileHandle.fileDescriptor

        // Set up a timeout
        let deadline = DispatchTime.now() + Self.commandTimeout

        // Read all lines into a buffer; keep the last JSON line as final response
        // Intermediate lines with {"status":"progress",...} update UI
        let readGroup = DispatchGroup()
        readGroup.enter()

        var lastJsonLine: Data?
        var stderrOutput = ""

        // stderr must be drained concurrently; otherwise a noisy Python process
        // can fill the pipe and deadlock before it reaches its final JSON line.
        let stderrGroup = DispatchGroup()
        stderrGroup.enter()
        DispatchQueue.global(qos: .background).async {
            defer { stderrGroup.leave() }
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
                stderrOutput = errStr
            }
        }

        // Read stdout line-by-line
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { readGroup.leave() }

            let stream = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: false)
            var partialLine = Data()

            while true {
                // availableData blocks until bytes or EOF. The owning queue
                // enforces the deadline below and terminates the child if needed.
                let chunk = stream.availableData
                if chunk.isEmpty {
                    // EOF
                    break
                }
                partialLine.append(chunk)

                // Process complete lines
                while let newlineRange = partialLine.range(of: Data("\n".utf8)) {
                    let lineData = partialLine.subdata(in: 0..<newlineRange.lowerBound)
                    partialLine.removeSubrange(0...newlineRange.lowerBound)

                    guard let lineStr = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !lineStr.isEmpty else { continue }

                    // Try parsing as JSON
                    if let jsonData = lineStr.data(using: .utf8),
                       let jsonObj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        let status = jsonObj["status"] as? String ?? ""

                        if status == "progress" {
                            // Update progress on main thread
                            let progress = jsonObj["progress"] as? Double ?? 0.0
                            let message = jsonObj["message_code"] as? String ?? "PROGRESS_START"
                            DispatchQueue.main.async { [weak self] in
                                if case .loading = self?.state {
                                    self?.state = .loading(progress: progress, message: message)
                                } else if case .processing = self?.state {
                                    self?.state = .processing(progress: progress)
                                }
                            }
                        } else {
                            // This is a final response line — keep the last one
                            lastJsonLine = lineData
                        }
                    }
                }
            }

        }

        if readGroup.wait(timeout: deadline) == .timedOut {
            // terminateProcess captures this exact child. Using currentProcess
            // here would be racy if state had already been reset.
            terminateProcess(process)
            process.waitUntilExit()
            readGroup.wait()
            stderrGroup.wait()
            throw ProcessError(code: "ERR_0001",
                               message: "Timeout — process exceeded \(Int(Self.commandTimeout))s")
        }

        process.waitUntilExit()
        stderrGroup.wait()
        let fullStderr = stderrOutput

        let logMsg = "[PythonBridge] exit=\(process.terminationStatus) stderr=\(fullStderr.prefix(500))"
        print(logMsg)

        if process.terminationStatus != 0 {
            throw ProcessError(code: "ERR_0005",
                               message: "Python crashed (exit \(process.terminationStatus)): \(fullStderr.prefix(200))")
        }

        guard let finalData = lastJsonLine else {
            throw ProcessError(code: "ERR_0006", message: "No response from Python engine. stderr: \(fullStderr.prefix(200))")
        }

        return finalData
    }

    /// Kill the currently running Python process
    private func killProcess() {
        guard let proc = currentProcess else { return }
        currentProcess = nil
        terminateProcess(proc)
    }

    /// Ask one specific child to stop, then force-kill that same child if it
    /// ignores SIGTERM. Capturing `proc` fixes the old bug where clearing
    /// currentProcess made the delayed SIGKILL a no-op.
    private func terminateProcess(_ proc: Process) {
        guard proc.isRunning else { return }
        let pid = proc.processIdentifier
        proc.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            if proc.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }
}

// MARK: - Error Code

struct ProcessError: LocalizedError {
    let code: String
    let message: String

    var errorDescription: String? { "\(code): \(message)" }
}

// MARK: - Preview response types (for bulk preview)

struct PreviewBulkResult: Codable {
    let status: String
    let data: [PreviewData]?
    let message: String?
    let errorCode: String?

    enum CodingKeys: String, CodingKey {
        case status, data, message
        case errorCode = "error_code"
    }
}

struct PreviewData: Codable {
    let filePath: String
    let fileName: String
    let width: Int?
    let height: Int?
    let bitDepth: Int?
    let estimatedFormat: String?
    let selectedFormat: String?
    let foundCount: Int?
    let expectedCount: Int?
    let refinementApplied: Bool?
    let refinementFallbackReason: String?
    let frames: [FilmFrame]?
    let previewB64: String?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case fileName = "file_name"
        case width, height
        case bitDepth = "bit_depth"
        case estimatedFormat = "estimated_format"
        case selectedFormat = "selected_format"
        case foundCount = "found_count"
        case expectedCount = "expected_count"
        case refinementApplied = "refinement_applied"
        case refinementFallbackReason = "refinement_fallback_reason"
        case frames
        case previewB64 = "preview_b64"
    }
}
