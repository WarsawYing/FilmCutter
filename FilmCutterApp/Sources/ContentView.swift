import SwiftUI
import UniformTypeIdentifiers

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject private var bridge: PythonBridge

    // Shared state for both Plan and Action stages
    @State private var rollName: String = ""
    @State private var outputDir: URL?
    @State private var showOutputPicker = false
    @State private var pendingMoveToAction = false
    @State private var invertColors: Bool = false
    @State private var borderPx: Double = 4
    @State private var selectedFormat: RollPreset = .auto
    @State private var selectedDetector: DetectorMode = .v2
    @State private var showRedetectConfirmation = false
    @FocusState private var isNameFocused: Bool
    @State private var metadata = RollMetadata()
    @State private var showMetadata = true

    var body: some View {
        VStack(spacing: 0) {
            // -------- Title Bar --------
            HStack(spacing: 10) {
                if let logo = NSImage(contentsOf: logoURL()) {
                    Image(nsImage: logo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 26)
                }
                Text("FilmCutter")
                    .font(.title.weight(.bold))
                    .foregroundColor(.primary)
                Spacer()
                if case .plan(_, _) = bridge.state {
                    Text("Plan Stage")
                        .font(.subheadline).foregroundColor(.secondary)
                } else if case .action(_, _, _) = bridge.state {
                    Text("Action Stage")
                        .font(.subheadline).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 36)
            .padding(.bottom, 10)
            .background(.bar)

            mainBody
        }
        .fileImporter(isPresented: $showOutputPicker,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result {
                guard let selectedFolder = urls.first else {
                    pendingMoveToAction = false
                    return
                }
                outputDir = selectedFolder
                if pendingMoveToAction {
                    pendingMoveToAction = false
                    // Auto-advance after folder selection
                    if case .plan(let plans, _) = bridge.state {
                        bridge.transitionToAction(
                            plans: plans,
                            rollName: rollName,
                            outputDir: selectedFolder.path
                        )
                    }
                }
            }
        }
    }

    // MARK: - Main Body

    @ViewBuilder
    private var mainBody: some View {
        switch bridge.state {
        case .idle:
            dropZoneView
        case .loading(let progress, let message):
            loadingView(progress: progress, message: message)
        case .plan(let plans, let currentIndex):
            planView(plans: plans, currentIndex: currentIndex)
        case .action(let plans, let name, let dir):
            actionView(plans: plans, initialRollName: name, initialOutputDir: dir)
        case .processing(let progress):
            processingView(progress: progress)
        case .failed(let error):
            failedView(error: error)
        case .completed(let files):
            completedView(files: files)
        }
    }

    // MARK: - Drop Zone

    private var dropZoneView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "film.stack")
                .font(.system(size: 72))
                .foregroundColor(.accentColor.opacity(0.5))
            VStack(spacing: 6) {
                Text("Drop a scanned film image here")
                    .font(.title2)
                    .foregroundColor(.primary)
                Text("Drop a single TIFF file, or a folder for batch processing")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            HStack(spacing: 16) {
                Button("Select File...") { openFilePicker() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Button("Select Folder...") { openFolderPicker() }
                    .buttonStyle(.bordered).controlSize(.large)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Loading with progress bar

    private func loadingView(progress: Double, message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            // White progress bar
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .white))
                .frame(width: 320)
                .scaleEffect(x: 1, y: 2, anchor: .center)
            
            // Percentage text
            Text("\(Int(progress * 100))%")
                .font(.largeTitle.weight(.bold))
                .foregroundColor(.white.opacity(0.8))
            
            // Status message
            Text(message)
                .font(.headline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Plan Stage

    private func planView(plans: [ScanPlan], currentIndex: Int) -> some View {
        let plan = plans[currentIndex]

        return HStack(spacing: 0) {
            // Left panel: controls
            VStack(alignment: .leading, spacing: 16) {
                // ---- Roll Name ----
                GroupBox("Roll Name") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Roll Name:").foregroundColor(.secondary).font(.callout)
                            TextField("e.g. Paris2026", text: $rollName)
                                .textFieldStyle(.roundedBorder)
                                .focused($isNameFocused)
                                .font(.body.weight(.medium))
                                .frame(minHeight: 28)
                        }

                        HStack {
                            Text("Type:").foregroundColor(.secondary).font(.callout)
                            Picker("", selection: $selectedFormat) {
                                ForEach(RollPreset.allCases, id: \.self) { preset in
                                    Text(preset.rawValue).tag(preset)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 200)
                        }

                        HStack {
                            Text("Detector:").foregroundColor(.secondary).font(.callout)
                            Picker("", selection: $selectedDetector) {
                                ForEach(DetectorMode.allCases, id: \.self) { detector in
                                    Text(detector.rawValue).tag(detector)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 200)
                        }

                        HStack {
                            Text("Neg/Pos:").foregroundColor(.secondary).font(.callout)
                            Picker("", selection: $invertColors) {
                                Text("Negative (invert)").tag(true)
                                Text("Positive (keep)").tag(false)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        HStack {
                            Text("Border: \(Int(borderPx)) px").font(.callout).foregroundColor(.secondary)
                            Slider(value: $borderPx, in: 0...20, step: 1)
                                .frame(width: 120)
                        }
                    }
                }

                // ---- Roll Metadata (collapsible) ----
                DisclosureGroup(isExpanded: $showMetadata) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Row 1: Camera | Lens
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Camera:").foregroundColor(.secondary).font(.caption)
                                SuggestField(text: $metadata.camera, suggestions: CameraLensMemory.rememberedCameras())
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lens:").foregroundColor(.secondary).font(.caption)
                                SuggestField(text: $metadata.lens, suggestions: CameraLensMemory.rememberedLenses())
                            }
                        }

                        // Row 2: Film Stock | Push/Pull
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Film:").foregroundColor(.secondary).font(.caption)
                                Picker("", selection: $metadata.filmStock) {
                                    Text("(none)").tag("")
                                    ForEach(FilmStockPresets.groups) { group in
                                        Divider()
                                        Text("── \(group.groupName) ──").tag("")
                                        ForEach(group.stocks, id: \.self) { stock in
                                            Text(stock).tag(stock)
                                        }
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: 160)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Push/Pull:").foregroundColor(.secondary).font(.caption)
                                Picker("", selection: $metadata.pushPull) {
                                    ForEach(PushPullPresets.all, id: \.self) { pp in
                                        Text(pp).tag(pp)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: 80)
                            }
                        }

                        // Row 3: Aperture | Date
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Aperture:").foregroundColor(.secondary).font(.caption)
                                Picker("", selection: $metadata.aperture) {
                                    ForEach(AperturePresets.all, id: \.self) { ap in
                                        Text(ap).tag(ap)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: 120)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Date:").foregroundColor(.secondary).font(.caption)
                                HStack(spacing: 4) {
                                    TextField("YYYY-MM-DD", text: $metadata.date)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                        .frame(width: 100)
                                    Button {
                                        let formatter = DateFormatter()
                                        formatter.dateFormat = "yyyy-MM-dd"
                                        metadata.date = formatter.string(from: Date())
                                    } label: {
                                        Text("Today").font(.caption2)
                                    }
                                }
                            }
                        }

                        // Row 4: Scanner
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scanner:").foregroundColor(.secondary).font(.caption)
                            Picker("", selection: $metadata.scanner) {
                                Text("(none)").tag("")
                                ForEach(ScannerPresets.all, id: \.self) { s in
                                    Text(s).tag(s)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 280)
                        }

                        // Row 5: Notes
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notes:").foregroundColor(.secondary).font(.caption)
                            TextField("e.g. Paris afternoon light, tripod used", text: $metadata.notes)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text("Roll Metadata").font(.headline)
                }

                // ---- Scan Info ----
                GroupBox("Scan \(currentIndex + 1) of \(plans.count)") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("File:").foregroundColor(.secondary)
                            Text(plan.originalName).lineLimit(1).truncationMode(.middle)
                        }
                        HStack {
                            Text("Size:").foregroundColor(.secondary)
                            Text("\(plan.imageWidth) × \(plan.imageHeight) px")
                        }
                        HStack {
                            Text("Depth:").foregroundColor(.secondary)
                            Text("\(plan.bitDepth)-bit")
                        }
                        HStack {
                            Text("Frames:").foregroundColor(.secondary)
                            Text("\(plan.frameCount) detected")
                                .foregroundColor(plan.frameCount > 0 ? .green : .red)
                                .fontWeight(.semibold)
                        }
                        if plan.hasManualEdits {
                            Label("Manual adjustments", systemImage: "hand.draw")
                                .foregroundColor(.orange)
                        }
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ---- Navigation (multi-scan) ----
                if plans.count > 1 {
                    HStack(spacing: 12) {
                        Button {
                            updateAndNavigate(plans: plans, currentIndex: currentIndex, direction: -1)
                        } label: {
                            Label("Prev", systemImage: "chevron.left")
                        }
                        .disabled(currentIndex <= 0)
                        .buttonStyle(.bordered)

                        Text("Scan \(currentIndex + 1)/\(plans.count)")
                            .font(.headline)

                        Button {
                            updateAndNavigate(plans: plans, currentIndex: currentIndex, direction: 1)
                        } label: {
                            Label("Next", systemImage: "chevron.right")
                        }
                        .disabled(currentIndex >= plans.count - 1)
                        .buttonStyle(.bordered)
                    }
                }

                // ---- Update & Approve ----
                HStack(spacing: 12) {
                    Button("Re-detect") {
                        if plan.hasManualEdits {
                            showRedetectConfirmation = true
                        } else {
                            updateCurrentScan(plans: plans, currentIndex: currentIndex)
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Run the selected detector again")

                    Spacer()

                    Button("Approve & Cut \(totalPlannedFrames(plans)) Frames →") {
                        moveToAction(plans: plans)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(rollName.isEmpty || totalPlannedFrames(plans) == 0)
                }

                Spacer()
            }
            .padding()
            .frame(minWidth: 280, maxWidth: 340)
            .background(Color(NSColor.controlBackgroundColor))

            // Right panel: interactive frame editor canvas
            FrameCanvasView(
                plan: plan,
                originalImageWidth: plan.imageWidth,
                originalImageHeight: plan.imageHeight,
                nsImage: loadPreviewImage(for: currentIndex, in: plans),
                onFramesChanged: { newFrames in
                    var updated = plans
                    updated[currentIndex].detectedFrames = newFrames
                    updated[currentIndex].hasManualEdits =
                        newFrames != updated[currentIndex].automaticFrames
                    bridge.transitionToPlan(updated, index: currentIndex)
                }
            )
            .frame(minWidth: 400)
        }
        .alert("Replace manual adjustments?", isPresented: $showRedetectConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Re-detect", role: .destructive) {
                updateCurrentScan(plans: plans, currentIndex: currentIndex)
            }
        } message: {
            Text("The automatic baseline will be replaced. You can still edit or reset the new result.")
        }
        .onAppear {
            isNameFocused = true
            selectedFormat = plan.rollPreset
            selectedDetector = plan.detectorMode
        }
    }

    // MARK: - Action Stage

    private func actionView(plans: [ScanPlan], initialRollName: String, initialOutputDir: String) -> some View {
        let totalFrames = plans.reduce(0) { $0 + $1.frameCount }

        return VStack(spacing: 16) {
            // ---- Header ----
            GroupBox("Action Stage: Ready to Cut") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Roll Name:").foregroundColor(.secondary)
                        TextField("Roll name", text: $rollName)
                            .textFieldStyle(.roundedBorder)
                            .focused($isNameFocused)
                            .frame(width: 250)
                            .font(.body.weight(.medium))
                    }

                    HStack(spacing: 24) {
                        Label("\(totalFrames) frames total", systemImage: "rectangle.split.2x2")
                        Label("\(plans.count) scan(s)", systemImage: "doc.on.doc")
                        Label(selectedFormat.rawValue, systemImage: "rectangle.ratio.4to3")
                        Label("\(invertColors ? "Negative" : "Positive")", systemImage: invertColors ? "circle.lefthalf.filled" : "circle")
                    }

                    HStack(spacing: 12) {
                        Text("Output:").foregroundColor(.secondary)
                        Text(outputDir?.path ?? initialOutputDir)
                            .lineLimit(1).truncationMode(.middle)
                            .font(.caption)
                        Button("Change...") { showOutputPicker = true }
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            .padding(.horizontal)

            // ---- Per-Scan Summary ----
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(plans) { plan in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan \(plan.id + 1): \(plan.originalName)")
                                    .font(.headline)
                                Text("\(plan.frameCount) frames · \(plan.imageWidth)×\(plan.imageHeight)px · \(plan.bitDepth)-bit · \(plan.rollPreset.rawValue)")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(plan.frameCount) frames")
                                .font(.callout).foregroundColor(.accentColor)
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            // ---- Action ----
            HStack(spacing: 16) {
                Button("Cancel") { bridge.reset() }
                    .buttonStyle(.bordered).controlSize(.large)

                Button(rollName.isEmpty ? "Enter a roll name first" : "Cut \(totalFrames) Frames →") {
                    startCutting(plans: plans)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(rollName.isEmpty || rollName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            isNameFocused = true
        }
    }

    // MARK: - Processing / Failed / Completed

    private func processingView(progress: Double) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView(value: progress, total: 1.0) {
                Text("Cutting frames...").font(.headline)
            }
            .progressViewStyle(.linear).frame(width: 300)
            Text("\(Int(progress * 100))%").font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func failedView(error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40)).foregroundColor(.orange)
            Text("Error").font(.headline)
            Text(error).font(.caption).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Try Again") { bridge.reset() }.buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func completedView(files: [String]) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 50)).foregroundColor(.green)
            Text("Successfully cut \(files.count) frames!").font(.headline)
            if !files.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                            Text(URL(fileURLWithPath: file).lastPathComponent)
                                .font(.caption)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 40)
            }
            HStack(spacing: 12) {
                Button("Open Output Folder") {
                    if let dir = outputDir { NSWorkspace.shared.open(dir) }
                }.buttonStyle(.borderedProminent)
                Button("Process Another") { bridge.reset() }.buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.tiff]
        panel.message = "Select a scanned film TIFF file"
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFiles([url])
    }

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Select a folder of TIFF files"
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let tiffFiles = scanTiffFiles(in: url)
        guard !tiffFiles.isEmpty else { return }
        
        if outputDir == nil { outputDir = url }
        loadFiles(tiffFiles)
    }

    private func loadFiles(_ urls: [URL]) {
        if rollName.isEmpty {
            rollName = urls.first?.deletingPathExtension().lastPathComponent ?? "Roll"
        }
        // Detection returns the content rectangle. Border is intentionally
        // deferred to export so changing the slider never requires re-detection.
        bridge.loadScanPlans(files: urls.map { $0.path },
                             format: selectedFormat.identifier,
                             detector: selectedDetector,
                             borderPx: 0)
    }

    /// Move to action stage with current plan state
    private func moveToAction(plans: [ScanPlan]) {
        guard let outDir = outputDir else {
            pendingMoveToAction = true
            showOutputPicker = true
            return
        }
        pendingMoveToAction = false
        rememberMetadata()
        bridge.transitionToAction(plans: plans, rollName: rollName, outputDir: outDir.path)
    }

    /// Start the actual cutting
    private func startCutting(plans: [ScanPlan]) {
        guard let outDir = outputDir else { return }
        rememberMetadata()
        bridge.cutAll(plans: plans, rollName: rollName,
                       outputDir: outDir.path,
                       invert: invertColors, borderPx: Int(borderPx),
                       metadata: metadata)
    }

    private func rememberMetadata() {
        if !metadata.camera.isEmpty { CameraLensMemory.rememberCamera(metadata.camera) }
        if !metadata.lens.isEmpty { CameraLensMemory.rememberLens(metadata.lens) }
    }

    /// Explicitly re-run detection.  Callers are responsible for confirming
    /// replacement when the plan contains manual edits.
    private func updateCurrentScan(
        plans: [ScanPlan],
        currentIndex: Int,
        completion: (([ScanPlan]) -> Void)? = nil
    ) {
        guard case .plan(let currentPlans, _) = bridge.state else { return }
        let currentPlan = currentPlans[currentIndex]

        bridge.redetect(filePath: currentPlan.filePath,
                        format: selectedFormat.identifier,
                        detector: selectedDetector,
                        borderPx: 0) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    if let frames = data.frames {
                        var updated = currentPlans
                        updated[currentIndex].detectedFrames = frames
                        updated[currentIndex].automaticFrames = frames
                        updated[currentIndex].hasManualEdits = false
                        updated[currentIndex].detectorMode = self.selectedDetector
                        updated[currentIndex].rollPreset = self.selectedFormat
                        updated[currentIndex].imageWidth = data.width ?? currentPlan.imageWidth
                        updated[currentIndex].imageHeight = data.height ?? currentPlan.imageHeight
                        updated[currentIndex].previewB64 = data.previewB64 ?? currentPlans[currentIndex].previewB64
                        self.bridge.transitionToPlan(updated, index: currentIndex)
                        completion?(updated)
                    } else {
                        completion?(currentPlans)
                    }
                case .failure:
                    completion?(currentPlans)
                }
            }
        }
    }

    /// Navigate to next/previous scan, updating current one first
    private func updateAndNavigate(plans: [ScanPlan], currentIndex: Int, direction: Int) {
        let newIndex = currentIndex + direction
        guard newIndex >= 0 && newIndex < plans.count else { return }
        
        // Navigation never triggers detection.  This prevents an accidental
        // format-picker change from overwriting a scan the user just edited.
        bridge.transitionToPlan(plans, index: newIndex)
        selectedFormat = plans[newIndex].rollPreset
        selectedDetector = plans[newIndex].detectorMode
    }

    // MARK: - Helpers

    private func logoURL() -> URL {
        Bundle.module.url(forResource: "logo", withExtension: "svg")
            ?? URL(fileURLWithPath: "")
    }

    private func totalPlannedFrames(_ plans: [ScanPlan]) -> Int {
        plans.reduce(0) { $0 + $1.frameCount }
    }

    private func scanTiffFiles(in folderURL: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        var tiffFiles: [URL] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "tif" || ext == "tiff" {
                tiffFiles.append(fileURL)
            }
        }
        tiffFiles.sort { $0.lastPathComponent < $1.lastPathComponent }
        return tiffFiles
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSURL.self) { nsurl, error in
            guard let url = nsurl as? URL else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
            DispatchQueue.main.async {
                if isDir.boolValue {
                    let tiffFiles = self.scanTiffFiles(in: url)
                    guard !tiffFiles.isEmpty else { return }
                    if self.outputDir == nil { self.outputDir = url }
                    self.loadFiles(tiffFiles)
                } else {
                    let ext = url.pathExtension.lowercased()
                    guard ext == "tif" || ext == "tiff" else { return }
                    self.loadFiles([url])
                }
            }
        }
        return true
    }

    /// Load a preview image from base64 stored in the ScanPlan
    private func loadPreviewImage(for index: Int, in plans: [ScanPlan]) -> NSImage? {
        guard index < plans.count, let b64 = plans[index].previewB64,
              let data = Data(base64Encoded: b64) else { return nil }
        return NSImage(data: data)
    }
}

// MARK: - Interactive Frame Canvas

/// Interactive view that shows the preview image with draggable/resizable frame overlays.
struct FrameCanvasView: View {
    let plan: ScanPlan
    let originalImageWidth: Int
    let originalImageHeight: Int
    let nsImage: NSImage?
    let onFramesChanged: ([FilmFrame]) -> Void

    // Local copy of frames for drag editing
    @State private var frames: [FilmFrame] = []
    @State private var selectedFrameIndex: Int? = nil
    @State private var keyMonitor: Any? = nil
    @State private var undoStack: [[FilmFrame]] = []
    @State private var redoStack: [[FilmFrame]] = []

    // Gesture-driven transient state — NOT committed to frames until onEnded
    @GestureState private var moveTranslation: CGSize = .zero
    @GestureState private var resizeTranslation: CGSize = .zero
    @State private var moveTargetIndex: Int? = nil
    @State private var moveStartOrigin: (x: CGFloat, y: CGFloat)? = nil
    @State private var resizeTargetIndex: Int? = nil
    @State private var resizeTargetCorner: ResizeCorner? = nil
    @State private var resizeStartFrame: FilmFrame? = nil

    // Parameters for hit testing
    private let handleSize: CGFloat = 16
    private let minFrameSize: CGFloat = 20  // min 20px in display coords

    enum ResizeCorner: String, Equatable {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
    }

    init(plan: ScanPlan, originalImageWidth: Int, originalImageHeight: Int,
         nsImage: NSImage?, onFramesChanged: @escaping ([FilmFrame]) -> Void) {
        self.plan = plan
        self.originalImageWidth = originalImageWidth
        self.originalImageHeight = originalImageHeight
        self.nsImage = nsImage
        self.onFramesChanged = onFramesChanged
        self._frames = State(initialValue: plan.detectedFrames)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text("Drag frames to adjust — \(frames.count) frame(s)")
                .font(.headline).padding(.top, 6)
            Divider()

            GeometryReader { geo in
                let canvasSize = geo.size
                let displayScale = computeDisplayScale(canvasSize: canvasSize)
                let displayW = originalImageWidth > 0 ? CGFloat(originalImageWidth) * displayScale : canvasSize.width
                let displayH = originalImageHeight > 0 ? CGFloat(originalImageHeight) * displayScale : canvasSize.height

                ZStack {
                    // Background
                    Color(NSColor.controlBackgroundColor)

                    // Image + frame overlays share a top-leading aligned container
                    // so frame positions align with the image (same coordinate origin)
                    ZStack(alignment: .topLeading) {
                        if let img = nsImage {
                            Image(nsImage: img)
                                .resizable()
                                .interpolation(.medium)
                                .frame(width: displayW, height: displayH)
                        } else {
                            Text("No preview available")
                                .foregroundColor(.secondary)
                                .frame(width: displayW, height: displayH)
                        }

                        ForEach(Array(frames.enumerated()), id: \.offset) { idx, frame in
                            frameOverlay(frame: frame, displayScale: displayScale, index: idx)
                        }
                    }
                    .frame(width: displayW, height: displayH)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }

            // Keep editing controls in their own fixed row.  Overlaying this
            // toolbar on the GeometryReader let a tall portrait preview grow
            // underneath it and pushed the controls against the window edge.
            HStack(spacing: 12) {
                Button("+ Add Frame") {
                    addFrame()
                }
                .buttonStyle(.bordered).controlSize(.small)

                if selectedFrameIndex != nil {
                    Button("Delete Selected") {
                        deleteSelected()
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .foregroundColor(.red)
                }

                Button("Undo") {
                    undo()
                }
                .disabled(undoStack.isEmpty)
                .buttonStyle(.bordered).controlSize(.small)

                Button("Redo") {
                    redo()
                }
                .disabled(redoStack.isEmpty)
                .buttonStyle(.bordered).controlSize(.small)

                Button("Reset Auto") {
                    commitFrames(plan.automaticFrames)
                    selectedFrameIndex = nil
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
        .onChange(of: plan.detectedFrames) {
            // Parent updates echo local commits back into this view.  Ignore
            // equal values so a drag does not destroy its undo history.
            if frames != plan.detectedFrames {
                frames = plan.detectedFrames
                undoStack.removeAll()
                redoStack.removeAll()
                selectedFrameIndex = nil
            }
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 51 || event.keyCode == 117 {
                    if selectedFrameIndex != nil {
                        deleteSelected()
                        return nil
                    }
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }

    // MARK: - Visual Frame Rect (incorporates active gesture offsets)

    private func visualFrameRect(frame: FilmFrame, displayScale: CGFloat, index: Int) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var vx = CGFloat(frame.x)
        var vy = CGFloat(frame.y)
        var vw = CGFloat(frame.width)
        var vh = CGFloat(frame.height)

        // Apply move gesture offset (visual only, not committed)
        if moveTargetIndex == index, let start = moveStartOrigin {
            vx = start.x + moveTranslation.width / displayScale
            vy = start.y + moveTranslation.height / displayScale
            vx = max(0, min(vx, CGFloat(originalImageWidth) - vw))
            vy = max(0, min(vy, CGFloat(originalImageHeight) - vh))
        }

        // Apply resize gesture offset (visual only, not committed)
        if resizeTargetIndex == index, let start = resizeStartFrame, let corner = resizeTargetCorner {
            let rdx = resizeTranslation.width / displayScale
            let rdy = resizeTranslation.height / displayScale
            switch corner {
            case .topLeft:
                vx = CGFloat(start.x) + rdx
                vy = CGFloat(start.y) + rdy
                vw = CGFloat(start.width) - rdx
                vh = CGFloat(start.height) - rdy
            case .topRight:
                vy = CGFloat(start.y) + rdy
                vw = CGFloat(start.width) + rdx
                vh = CGFloat(start.height) - rdy
            case .bottomLeft:
                vx = CGFloat(start.x) + rdx
                vw = CGFloat(start.width) - rdx
                vh = CGFloat(start.height) + rdy
            case .bottomRight:
                vw = CGFloat(start.width) + rdx
                vh = CGFloat(start.height) + rdy
            case .top:
                vy = CGFloat(start.y) + rdy
                vh = CGFloat(start.height) - rdy
            case .bottom:
                vh = CGFloat(start.height) + rdy
            case .left:
                vx = CGFloat(start.x) + rdx
                vw = CGFloat(start.width) - rdx
            case .right:
                vw = CGFloat(start.width) + rdx
            }
            vw = max(minFrameSize / displayScale, min(vw, CGFloat(originalImageWidth)))
            vh = max(minFrameSize / displayScale, min(vh, CGFloat(originalImageHeight)))
            vx = max(0, min(vx, CGFloat(originalImageWidth) - vw))
            vy = max(0, min(vy, CGFloat(originalImageHeight) - vh))
        }

        return (vx, vy, vw, vh)
    }

    // MARK: - Frame Overlay with Drag Gestures

    private func frameOverlay(frame: FilmFrame, displayScale: CGFloat, index: Int) -> some View {
        let isSelected = selectedFrameIndex == index
        let (vx, vy, vw, vh) = visualFrameRect(frame: frame, displayScale: displayScale, index: index)
        let dx = vx * displayScale
        let dy = vy * displayScale
        let dw = vw * displayScale
        let dh = vh * displayScale

        let color: Color = isSelected ? .orange : frameColors[index % frameColors.count]

        return ZStack {
            Rectangle()
                .fill(color.opacity(0.08))
                .overlay(
                    Rectangle()
                        .stroke(color, lineWidth: isSelected ? 3 : 2)
                )

            Text("\(index + 1)")
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
                .padding(3)
                .background(color.opacity(0.8))
                .cornerRadius(3)
                .offset(x: 4, y: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: max(dw, 1), height: max(dh, 1))
        .position(x: dx + dw / 2, y: dy + dh / 2)
        .simultaneousGesture(
            TapGesture().onEnded {
                selectedFrameIndex = index
            }
        )
        .gesture(
            DragGesture(minimumDistance: 5)
                .updating($moveTranslation) { value, state, _ in
                    state = value.translation
                }
                .onChanged { _ in
                    if moveTargetIndex == nil {
                        moveTargetIndex = index
                        moveStartOrigin = (CGFloat(frame.x), CGFloat(frame.y))
                        selectedFrameIndex = index
                    }
                }
                .onEnded { val in
                    if let start = moveStartOrigin, moveTargetIndex == index {
                        let newX = max(0, start.x + val.translation.width / displayScale)
                        let newY = max(0, start.y + val.translation.height / displayScale)
                        let clampedX = min(newX, CGFloat(originalImageWidth) - CGFloat(frame.width))
                        let clampedY = min(newY, CGFloat(originalImageHeight) - CGFloat(frame.height))
                        var updated = frames
                        updated[index] = FilmFrame(
                            index: index,
                            x: Int(clampedX),
                            y: Int(clampedY),
                            width: frame.width,
                            height: frame.height
                        )
                        commitFrames(updated)
                    }
                    moveTargetIndex = nil
                    moveStartOrigin = nil
                }
        )
        .overlay(
            isSelected
                ? AnyView(resizeHandles(
                    frameIndex: index,
                    displayScale: displayScale,
                    displayWidth: dw,
                    displayHeight: dh
                ))
                : AnyView(EmptyView())
        )
    }

    // MARK: - Resize Handles

    private func resizeHandles(
        frameIndex: Int,
        displayScale: CGFloat,
        displayWidth: CGFloat,
        displayHeight: CGFloat
    ) -> some View {
        guard frameIndex < frames.count else { return AnyView(EmptyView()) }

        let hs = handleSize
        let half = hs / 2

        // This view is an overlay of one frame rectangle, so its origin is
        // local to that rectangle. Using canvas-level x/y here displaced the
        // handles by the frame's position a second time.
        return AnyView(
            ZStack {
                handleRect(at: CGPoint(x: -half, y: -half), size: hs, corner: .topLeft, frameIndex: frameIndex, displayScale: displayScale)
                handleRect(at: CGPoint(x: displayWidth - half, y: -half), size: hs, corner: .topRight, frameIndex: frameIndex, displayScale: displayScale)
                handleRect(at: CGPoint(x: -half, y: displayHeight - half), size: hs, corner: .bottomLeft, frameIndex: frameIndex, displayScale: displayScale)
                handleRect(at: CGPoint(x: displayWidth - half, y: displayHeight - half), size: hs, corner: .bottomRight, frameIndex: frameIndex, displayScale: displayScale)

                handleRect(at: CGPoint(x: displayWidth / 2 - half, y: -half), size: hs, corner: .top, frameIndex: frameIndex, displayScale: displayScale)
                handleRect(at: CGPoint(x: displayWidth / 2 - half, y: displayHeight - half), size: hs, corner: .bottom, frameIndex: frameIndex, displayScale: displayScale)
                handleRect(at: CGPoint(x: -half, y: displayHeight / 2 - half), size: hs, corner: .left, frameIndex: frameIndex, displayScale: displayScale)
                handleRect(at: CGPoint(x: displayWidth - half, y: displayHeight / 2 - half), size: hs, corner: .right, frameIndex: frameIndex, displayScale: displayScale)
            }
        )
    }

    private func handleRect(at position: CGPoint, size: CGFloat,
                            corner: ResizeCorner, frameIndex: Int,
                            displayScale: CGFloat) -> some View {
        Rectangle()
            .fill(Color.orange)
            .frame(width: size, height: size)
            .position(x: position.x + size / 2, y: position.y + size / 2)
            .highPriorityGesture(
                DragGesture()
                    .updating($resizeTranslation) { value, state, _ in
                        state = value.translation
                    }
                    .onChanged { _ in
                        if resizeTargetIndex == nil {
                            resizeTargetIndex = frameIndex
                            resizeTargetCorner = corner
                            resizeStartFrame = frames[frameIndex]
                            selectedFrameIndex = frameIndex
                        }
                    }
                    .onEnded { val in
                        if let start = resizeStartFrame, let rcorner = resizeTargetCorner,
                           resizeTargetIndex == frameIndex {
                            let rdx = val.translation.width / displayScale
                            let rdy = val.translation.height / displayScale
                            var nx = CGFloat(start.x)
                            var ny = CGFloat(start.y)
                            var nw = CGFloat(start.width)
                            var nh = CGFloat(start.height)

                            switch rcorner {
                            case .topLeft:
                                nx = CGFloat(start.x) + rdx
                                ny = CGFloat(start.y) + rdy
                                nw = CGFloat(start.width) - rdx
                                nh = CGFloat(start.height) - rdy
                            case .topRight:
                                ny = CGFloat(start.y) + rdy
                                nw = CGFloat(start.width) + rdx
                                nh = CGFloat(start.height) - rdy
                            case .bottomLeft:
                                nx = CGFloat(start.x) + rdx
                                nw = CGFloat(start.width) - rdx
                                nh = CGFloat(start.height) + rdy
                            case .bottomRight:
                                nw = CGFloat(start.width) + rdx
                                nh = CGFloat(start.height) + rdy
                            case .top:
                                ny = CGFloat(start.y) + rdy
                                nh = CGFloat(start.height) - rdy
                            case .bottom:
                                nh = CGFloat(start.height) + rdy
                            case .left:
                                nx = CGFloat(start.x) + rdx
                                nw = CGFloat(start.width) - rdx
                            case .right:
                                nw = CGFloat(start.width) + rdx
                            }

                            nw = max(minFrameSize / displayScale, min(nw, CGFloat(originalImageWidth)))
                            nh = max(minFrameSize / displayScale, min(nh, CGFloat(originalImageHeight)))
                            nx = max(0, min(nx, CGFloat(originalImageWidth) - nw))
                            ny = max(0, min(ny, CGFloat(originalImageHeight) - nh))

                            var updated = frames
                            updated[frameIndex] = FilmFrame(
                                index: frameIndex,
                                x: Int(nx),
                                y: Int(ny),
                                width: Int(nw),
                                height: Int(nh)
                            )
                            commitFrames(updated)
                        }
                        resizeTargetIndex = nil
                        resizeTargetCorner = nil
                        resizeStartFrame = nil
                    }
            )
    }

    // MARK: - Helpers

    private func computeDisplayScale(canvasSize: CGSize) -> CGFloat {
        guard originalImageWidth > 0, originalImageHeight > 0 else { return 1 }
        let scaleX = canvasSize.width / CGFloat(originalImageWidth)
        let scaleY = canvasSize.height / CGFloat(originalImageHeight)
        // Use fit scaling (letterbox)
        return min(scaleX, scaleY)
    }

    private func addFrame() {
        // Match the median detected/user frame so adding to a vertical strip
        // does not unexpectedly create a landscape 3:2 rectangle.
        let sortedWidths = frames.map(\.width).sorted()
        let sortedHeights = frames.map(\.height).sorted()
        let sourceWidth = CGFloat(originalImageWidth)
        let sourceHeight = CGFloat(originalImageHeight)
        let portraitScan = sourceHeight > sourceWidth
        let fallbackWidth = portraitScan
            ? min(sourceWidth * 0.4, sourceHeight / 1.5)
            : min(sourceWidth / 6, sourceHeight * 1.5)
        let fallbackHeight = portraitScan
            ? fallbackWidth * 1.5
            : fallbackWidth / 1.5
        let fw = sortedWidths.isEmpty
            ? fallbackWidth
            : CGFloat(sortedWidths[sortedWidths.count / 2])
        let fh = sortedHeights.isEmpty
            ? fallbackHeight
            : CGFloat(sortedHeights[sortedHeights.count / 2])
        let fx = (CGFloat(originalImageWidth) - fw) / 2
        let fy = (CGFloat(originalImageHeight) - fh) / 2
        let newFrame = FilmFrame(
            index: frames.count,
            x: Int(fx),
            y: Int(fy),
            width: Int(fw),
            height: Int(fh)
        )
        var updated = frames
        updated.append(newFrame)
        commitFrames(updated)
        selectedFrameIndex = updated.count - 1
    }

    private func deleteSelected() {
        guard let sel = selectedFrameIndex, sel < frames.count else { return }
        var updated = frames
        updated.remove(at: sel)
        commitFrames(reindexed(updated))
        selectedFrameIndex = nil
    }

    private func commitFrames(_ newFrames: [FilmFrame]) {
        let normalized = reindexed(newFrames)
        guard normalized != frames else { return }
        undoStack.append(frames)
        if undoStack.count > 50 {
            undoStack.removeFirst(undoStack.count - 50)
        }
        redoStack.removeAll()
        frames = normalized
        onFramesChanged(normalized)
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(frames)
        frames = previous
        selectedFrameIndex = nil
        onFramesChanged(previous)
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(frames)
        frames = next
        selectedFrameIndex = nil
        onFramesChanged(next)
    }

    private func reindexed(_ source: [FilmFrame]) -> [FilmFrame] {
        source.enumerated().map { index, frame in
            FilmFrame(
                index: index,
                x: frame.x,
                y: frame.y,
                width: frame.width,
                height: frame.height
            )
        }
    }

    private let frameColors: [Color] = [
        .red, .green, .blue, .yellow, .purple, .cyan,
        .orange, .mint, .indigo, .teal, .pink, .brown
    ]
}

// MARK: - SuggestField (TextField with remembered suggestions)

struct SuggestField: View {
    @Binding var text: String
    let suggestions: [String]

    var body: some View {
        HStack(spacing: 2) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(minWidth: 100)
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) { text = s }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 16)
            }
        }
    }
}
