import SwiftUI
import UniformTypeIdentifiers

private enum UpdateScope: String, CaseIterable { case current, all }

struct ContentView: View {
    @EnvironmentObject private var bridge: PythonBridge
    @EnvironmentObject private var locale: LocalizationStore

    @State private var rollName = ""
    @State private var outputDir: URL?
    @State private var invertColors = false
    @State private var borderPx = 4.0
    @State private var selectedFormat: RollPreset = .auto
    @State private var expectedCountText = ""
    @State private var refineContour = false
    @State private var updateScope: UpdateScope = .current
    @State private var metadata = RollMetadata()
    @State private var showMetadata = true
    @State private var showOutputPicker = false
    @State private var pendingMoveToAction = false
    @State private var pendingActionPlans: [ScanPlan]?
    @State private var editHistories: [Int: FrameEditHistory] = [:]
    @State private var isRedetecting = false
    @State private var redetectCancelled = false
    @State private var showRedetectConfirmation = false
    @State private var showReselectConfirmation = false
    @State private var inlineError: String?
    @FocusState private var isNameFocused: Bool

    private func t(_ key: String, _ args: CVarArg...) -> String { locale.text(key, arguments: args) }

    var body: some View {
        VStack(spacing: 0) {
            header
            mainBody
        }
        .environment(\.locale, locale.language.locale)
        .fileImporter(isPresented: $showOutputPicker, allowedContentTypes: [.folder]) { result in
            let shouldAdvance = pendingMoveToAction
            pendingMoveToAction = false
            guard case .success(let folder) = result else { pendingActionPlans = nil; return }
            outputDir = folder
            UserDefaults.standard.set(folder.path, forKey: "filmcutter.outputDirectory")
            if shouldAdvance, let plans = pendingActionPlans {
                moveToAction(plans: plans)
            }
            pendingActionPlans = nil
        }
        .alert(t("confirm.reselect.title"), isPresented: $showReselectConfirmation) {
            Button(t("cancel"), role: .cancel) {}
            Button(t("replace"), role: .destructive) { resetSessionAndPickInput() }
        } message: { Text(t("confirm.reselect.message")) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "film.stack.fill").font(.title2).foregroundColor(.accentColor)
            Text("FilmCutter").font(.title.weight(.bold))
            Spacer()
            Text(stageTitle).font(.subheadline).foregroundColor(.secondary)
            Menu {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        locale.language = language
                    } label: {
                        HStack {
                            Text(language.menuName)
                            if locale.language == language { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: { Image(systemName: "globe") }
            .menuStyle(.borderlessButton).frame(width: 30)
        }
        .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 10).background(.bar)
    }

    private var stageTitle: String {
        switch bridge.state {
        case .idle: return t("stage.import")
        case .plan: return t("stage.adjust")
        case .action: return t("stage.export")
        default: return "FilmCutter"
        }
    }

    @ViewBuilder private var mainBody: some View {
        switch bridge.state {
        case .idle: dropZone
        case .loading(let progress, let code): progressView(progress, locale.text(code))
        case .plan(let plans, let index): adjustmentView(plans: plans, currentIndex: index)
        case .action(let plans, _, _): exportView(plans: plans)
        case .processing(let progress): progressView(progress, t("processing"))
        case .failed(let code): failedView(code: code)
        case .completed(let files): completedView(files: files)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "film.stack").font(.system(size: 72)).foregroundColor(.accentColor.opacity(0.55))
            Text(t("drop.title")).font(.title2)
            Text(t("drop.subtitle")).foregroundColor(.secondary)
            HStack(spacing: 16) {
                Button(t("select.file"), action: openFilePicker).buttonStyle(.borderedProminent).controlSize(.large)
                Button(t("select.folder"), action: openFolderPicker).buttonStyle(.bordered).controlSize(.large)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
    }

    private func progressView(_ progress: Double, _ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            ProgressView(value: progress).frame(width: 320)
            Text("\(Int(progress * 100))%").font(.title.weight(.bold))
            Text(message).foregroundColor(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func adjustmentView(plans: [ScanPlan], currentIndex: Int) -> some View {
        let plan = plans[currentIndex]
        return HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox(t("roll.name")) {
                        VStack(alignment: .leading, spacing: 9) {
                            TextField(t("roll.placeholder"), text: $rollName).textFieldStyle(.roundedBorder).focused($isNameFocused)
                            HStack {
                                Text(t("film.format")).foregroundColor(.secondary)
                                Picker("", selection: $selectedFormat) {
                                    ForEach(RollPreset.allCases) { preset in
                                        Text(locale.text(preset.localizationKey)).tag(preset)
                                    }
                                }.labelsHidden()
                            }
                            TextField(t("expected.count"), text: $expectedCountText)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: expectedCountText) { _, value in
                                    expectedCountText = String(value.filter(\.isNumber).prefix(2))
                                }
                            Toggle(t("experimental.refine"), isOn: $refineContour)
                            Picker("", selection: $invertColors) {
                                Text(t("negative")).tag(true); Text(t("positive")).tag(false)
                            }.labelsHidden().pickerStyle(.segmented)
                            HStack {
                                Text(t("border", Int(borderPx))).foregroundColor(.secondary)
                                Slider(value: $borderPx, in: 0...20, step: 1)
                            }
                        }.padding(.vertical, 4)
                    }

                    metadataEditor

                    GroupBox(t("scan.info", currentIndex + 1, plans.count)) {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(t("file"), value: plan.originalName)
                            LabeledContent(t("size"), value: "\(plan.imageWidth) × \(plan.imageHeight) px")
                            LabeledContent(t("depth"), value: "\(plan.bitDepth)-bit")
                            Text(Int(expectedCountText).map { t("expected.found", $0, plan.frameCount) } ?? locale.plural("found.frames", count: plan.frameCount))
                                .foregroundColor(plan.frameCount > 0 ? .green : .red).fontWeight(.semibold)
                            if plan.hasManualEdits { Label(t("manual.adjustments"), systemImage: "hand.draw").foregroundColor(.orange) }
                            if let reason = plan.refinementFallbackReason { Text(locale.text("refine.\(reason)")).font(.caption).foregroundColor(.secondary) }
                        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if plans.count > 1 {
                        HStack {
                            Button(t("previous")) { navigate(plans, currentIndex, -1) }.disabled(currentIndex == 0)
                            Spacer(); Text("\(currentIndex + 1) / \(plans.count)")
                            Spacer(); Button(t("next")) { navigate(plans, currentIndex, 1) }.disabled(currentIndex == plans.count - 1)
                        }
                    }

                    HStack {
                        if isRedetecting {
                            ProgressView().controlSize(.small)
                            Button(t("cancel")) { redetectCancelled = true; bridge.cancelCurrentOperation() }
                        } else {
                            Picker("", selection: $updateScope) {
                                Text(t("scope.current")).tag(UpdateScope.current)
                                Text(t("scope.all")).tag(UpdateScope.all)
                            }.labelsHidden().frame(width: 145)
                            Button(t("update.detection")) {
                                let targets = updateScope == .all ? plans : [plan]
                                if targets.contains(where: \.hasManualEdits) { showRedetectConfirmation = true }
                                else { updateDetection(plans: plans, currentIndex: currentIndex) }
                            }
                        }
                    }
                    if let inlineError { Text(locale.text(inlineError)).font(.caption).foregroundColor(.red) }
                    Button(t("approve", totalFrames(plans))) { moveToAction(plans: plansSavingControls(plans, at: currentIndex)) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(validRollName.isEmpty || totalFrames(plans) == 0)
                    Button(t("select.input.again")) {
                        if plans.contains(where: \.hasManualEdits) { showReselectConfirmation = true }
                        else { resetSessionAndPickInput() }
                    }.buttonStyle(.link)
                }.padding()
            }.frame(minWidth: 280, idealWidth: 330, maxWidth: 380).background(Color(NSColor.controlBackgroundColor))

            FrameCanvasView(
                plan: plan, originalImageWidth: plan.imageWidth, originalImageHeight: plan.imageHeight,
                nsImage: previewImage(plan), history: historyBinding(for: plan.id), onFramesChanged: { frames in
                    var updated = plans
                    updated[currentIndex].detectedFrames = frames
                    updated[currentIndex].hasManualEdits = frames != updated[currentIndex].automaticFrames
                    bridge.transitionToPlan(updated, index: currentIndex)
                }
            ).id("\(plan.id)-\(plan.detectionRevision)").frame(minWidth: 420)
        }
        .alert(t("replace.title"), isPresented: $showRedetectConfirmation) {
            Button(t("cancel"), role: .cancel) {}
            Button(t("replace"), role: .destructive) { updateDetection(plans: plans, currentIndex: currentIndex) }
        } message: { Text(t("replace.message")) }
        .onAppear { loadControls(from: plan); isNameFocused = rollName.isEmpty }
    }

    private var metadataEditor: some View {
        DisclosureGroup(isExpanded: $showMetadata) {
            VStack(alignment: .leading, spacing: 6) {
                HStack { field(t("camera"), $metadata.camera, CameraLensMemory.rememberedCameras()); field(t("lens"), $metadata.lens, CameraLensMemory.rememberedLenses()) }
                HStack {
                    VStack(alignment: .leading) { Text(t("film.stock")).font(.caption); Picker("", selection: $metadata.filmStock) { Text("—").tag(""); ForEach(FilmStockPresets.allStocks, id: \.self) { Text($0).tag($0) } }.labelsHidden() }
                    VStack(alignment: .leading) { Text(t("push.pull")).font(.caption); Picker("", selection: $metadata.pushPull) { ForEach(PushPullPresets.all, id: \.self) { Text($0).tag($0) } }.labelsHidden() }
                }
                HStack { field(t("scanner"), $metadata.scanner, ScannerPresets.all); field(t("aperture"), $metadata.aperture, AperturePresets.all) }
                HStack {
                    VStack(alignment: .leading) { Text(t("date")).font(.caption); TextField("YYYY-MM-DD", text: $metadata.date).textFieldStyle(.roundedBorder) }
                    Button(t("today")) { metadata.date = Self.isoDate.string(from: Date()) }
                }
                VStack(alignment: .leading) { Text(t("notes")).font(.caption); TextField("", text: $metadata.notes).textFieldStyle(.roundedBorder) }
            }.padding(.vertical, 4)
        } label: { Text(t("metadata")).font(.headline) }
    }

    private func field(_ label: String, _ binding: Binding<String>, _ suggestions: [String]) -> some View {
        VStack(alignment: .leading) { Text(label).font(.caption); SuggestField(text: binding, suggestions: suggestions) }
    }

    private func exportView(plans: [ScanPlan]) -> some View {
        let count = totalFrames(plans)
        let names = outputNames(count: count)
        let collisions = names.filter { name in
            guard let outputDir else { return false }
            return FileManager.default.fileExists(atPath: outputDir.appendingPathComponent(name).path)
        }
        return VStack(spacing: 16) {
            GroupBox(t("stage.export")) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(t("roll.name"), text: $rollName).textFieldStyle(.roundedBorder).frame(width: 300)
                    LabeledContent(t("output"), value: outputDir?.path ?? "—")
                    Button(t("change")) { showOutputPicker = true }
                    if let first = names.first, let last = names.last {
                        LabeledContent(t("filename.preview"), value: t("name.preview", first, last))
                    }
                    if !collisions.isEmpty {
                        Label(t("ERR_OUTPUT_COLLISION"), systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                        Text(collisions.prefix(3).joined(separator: ", ")).font(.caption).foregroundColor(.secondary)
                    }
                    Text("\(plans.count) scans · \(count) \(t("frames"))").foregroundColor(.secondary)
                }.padding(4).frame(maxWidth: .infinity, alignment: .leading)
            }
            ScrollView { ForEach(plans) { plan in HStack { Text(plan.originalName); Spacer(); Text("\(plan.frameCount)") }.padding(8) } }
            Spacer()
            HStack {
                Button(t("back")) { bridge.transitionToPlan(plans, index: 0) }.buttonStyle(.bordered).controlSize(.large)
                Button(validRollName.isEmpty ? t("name.required") : t("export", count)) { startCutting(plans) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(validRollName.isEmpty || outputDir == nil || !collisions.isEmpty)
            }
        }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(code: String) -> some View {
        VStack(spacing: 16) {
            Spacer(); Image(systemName: "exclamationmark.triangle").font(.system(size: 42)).foregroundColor(.orange)
            Text(t("error")).font(.headline); Text(locale.text(code)).foregroundColor(.secondary)
            if case .failed = bridge.state {
                HStack { Button(t("back.adjust")) { bridge.restorePlanIfAvailable() }; Button(t("select.input.again")) { resetSessionAndPickInput() } }
            }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func completedView(files: [String]) -> some View {
        VStack(spacing: 16) {
            Spacer(); Image(systemName: "checkmark.circle").font(.system(size: 52)).foregroundColor(.green)
            Text(t("complete", files.count)).font(.headline)
            HStack {
                Button(t("open.output")) { if let outputDir { NSWorkspace.shared.open(outputDir) } }.buttonStyle(.borderedProminent)
                Button(t("process.another")) { resetSession() }.buttonStyle(.bordered)
            }; Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var validRollName: String { OutputNaming.sanitizedBaseName(rollName) }
    private func totalFrames(_ plans: [ScanPlan]) -> Int { plans.reduce(0) { $0 + $1.frameCount } }
    private func outputNames(count: Int) -> [String] { (1...max(0, count)).map { OutputNaming.filename(base: rollName, index: $0) } }

    private func loadControls(from plan: ScanPlan) {
        selectedFormat = plan.rollPreset
        expectedCountText = plan.expectedFrameCount.map(String.init) ?? ""
        refineContour = plan.useContourRefinement
    }

    private func navigate(_ plans: [ScanPlan], _ current: Int, _ delta: Int) {
        let next = current + delta
        guard plans.indices.contains(next) else { return }
        let saved = plansSavingControls(plans, at: current)
        bridge.transitionToPlan(saved, index: next); loadControls(from: saved[next])
    }

    private func plansSavingControls(_ plans: [ScanPlan], at index: Int) -> [ScanPlan] {
        guard plans.indices.contains(index) else { return plans }
        var saved = plans
        saved[index].rollPreset = selectedFormat
        saved[index].expectedFrameCount = Int(expectedCountText)
        saved[index].useContourRefinement = refineContour
        return saved
    }

    private static let isoDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func updateDetection(plans: [ScanPlan], currentIndex: Int) {
        inlineError = nil
        let indices = updateScope == .all ? Array(plans.indices) : [currentIndex]
        let baseline = plansSavingControls(plans, at: currentIndex)
        var candidates = baseline
        var historiesToReset: [Int] = []
        let expected = Int(expectedCountText)
        isRedetecting = true
        redetectCancelled = false
        func run(_ offset: Int) {
            guard !redetectCancelled else {
                isRedetecting = false
                bridge.transitionToPlan(baseline, index: currentIndex)
                return
            }
            guard offset < indices.count else {
                isRedetecting = false
                historiesToReset.forEach { editHistories[$0] = FrameEditHistory() }
                bridge.transitionToPlan(candidates, index: currentIndex)
                return
            }
            let index = indices[offset]
            bridge.redetect(filePath: candidates[index].filePath, format: selectedFormat.identifier,
                            expectedCount: expected, refineContour: refineContour) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let data):
                        guard let frames = data.frames else {
                            inlineError = "ERR_PREVIEW_PARTIAL"
                            isRedetecting = false
                            bridge.transitionToPlan(baseline, index: currentIndex)
                            return
                        }
                        candidates[index].detectedFrames = frames; candidates[index].automaticFrames = frames
                        candidates[index].hasManualEdits = false; candidates[index].rollPreset = selectedFormat
                        candidates[index].expectedFrameCount = expected; candidates[index].useContourRefinement = refineContour
                        candidates[index].refinementApplied = data.refinementApplied ?? false
                        candidates[index].refinementFallbackReason = data.refinementFallbackReason
                        candidates[index].previewB64 = data.previewB64 ?? candidates[index].previewB64
                        candidates[index].detectionRevision += 1
                        historiesToReset.append(candidates[index].id)
                        run(offset + 1)
                    case .failure(let error):
                        if !redetectCancelled { inlineError = (error as? ProcessError)?.code ?? "ERR_PREVIEW_PARTIAL" }
                        isRedetecting = false
                        bridge.transitionToPlan(baseline, index: currentIndex)
                    }
                }
            }
        }
        run(0)
    }

    private func moveToAction(plans: [ScanPlan]) {
        guard !validRollName.isEmpty else { return }
        if outputDir == nil {
            pendingMoveToAction = true
            pendingActionPlans = plans
            showOutputPicker = true
            return
        }
        rememberMetadata(); bridge.transitionToAction(plans: plans, rollName: rollName, outputDir: outputDir!.path)
    }

    private func startCutting(_ plans: [ScanPlan]) {
        guard let outputDir else { return }
        rememberMetadata(); bridge.cutAll(plans: plans, rollName: validRollName, outputDir: outputDir.path,
                                          invert: invertColors, borderPx: Int(borderPx), metadata: metadata)
    }

    private func rememberMetadata() {
        if !metadata.camera.isEmpty { CameraLensMemory.rememberCamera(metadata.camera) }
        if !metadata.lens.isEmpty { CameraLensMemory.rememberLens(metadata.lens) }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.tiff]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }; loadFiles([url], sourceFolder: nil)
    }

    private func openFolderPicker() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let files = scanTiffFiles(folder); guard !files.isEmpty else { return }; loadFiles(files, sourceFolder: folder)
    }

    private func loadFiles(_ urls: [URL], sourceFolder: URL?) {
        let sourceName = sourceFolder?.lastPathComponent ?? urls.first?.deletingPathExtension().lastPathComponent ?? "Film"
        rollName = sourceName
        if outputDir == nil {
            if let remembered = UserDefaults.standard.string(forKey: "filmcutter.outputDirectory") { outputDir = URL(fileURLWithPath: remembered) }
            else { outputDir = (sourceFolder ?? urls[0].deletingLastPathComponent()).appendingPathComponent("FilmCutter Output") }
        }
        bridge.loadScanPlans(files: urls.map(\.path), format: "auto")
    }

    private func resetSessionAndPickInput() { resetSession(); openFolderPicker() }
    private func resetSession() {
        rollName = ""; outputDir = nil; metadata = RollMetadata(); selectedFormat = .auto
        expectedCountText = ""; refineContour = false; inlineError = nil; editHistories = [:]
        pendingActionPlans = nil; isRedetecting = false; redetectCancelled = false; bridge.reset()
    }

    private func scanTiffFiles(_ folder: URL) -> [URL] {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var result: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if ["tif", "tiff"].contains(url.pathExtension.lowercased()) { result.append(url) }
        }
        return InputOrdering.naturalSort(result)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSURL.self) { object, _ in
            guard let url = object as? URL else { return }
            var directory: ObjCBool = false; FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            DispatchQueue.main.async {
                if directory.boolValue { let files = scanTiffFiles(url); if !files.isEmpty { loadFiles(files, sourceFolder: url) } }
                else if ["tif", "tiff"].contains(url.pathExtension.lowercased()) { loadFiles([url], sourceFolder: nil) }
            }
        }; return true
    }

    private func previewImage(_ plan: ScanPlan) -> NSImage? {
        guard let text = plan.previewB64, let data = Data(base64Encoded: text) else { return nil }; return NSImage(data: data)
    }

    private func historyBinding(for id: Int) -> Binding<FrameEditHistory> {
        Binding(
            get: { editHistories[id] ?? FrameEditHistory() },
            set: { editHistories[id] = $0 }
        )
    }
}

enum OutputNaming {
    static func sanitizedBaseName(_ source: String) -> String {
        let controls = CharacterSet.controlCharacters
        let cleaned = source.unicodeScalars.map { scalar -> String in
            if controls.contains(scalar) || "/\\:*?\"<>|".unicodeScalars.contains(scalar) { return "-" }
            return String(scalar)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ".-_ "))
    }
    static func filename(base: String, index: Int) -> String {
        "\(sanitizedBaseName(base))_\(String(format: "%03d", index)).tif"
    }
}

enum InputOrdering {
    static func naturalSort(_ urls: [URL]) -> [URL] {
        urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}

// MARK: - Interactive Frame Canvas

fileprivate struct FrameCanvasView: View {
    @EnvironmentObject private var locale: LocalizationStore
    let plan: ScanPlan
    let originalImageWidth: Int
    let originalImageHeight: Int
    let nsImage: NSImage?
    @Binding var history: FrameEditHistory
    let onFramesChanged: ([FilmFrame]) -> Void
    @State private var frames: [FilmFrame] = []
    @State private var selectedFrameIndex: Int?
    @GestureState private var translation: CGSize = .zero
    @State private var dragIndex: Int?
    @State private var dragStart: FilmFrame?
    @State private var resizeIndex: Int?
    @State private var resizeStart: FilmFrame?

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let layout = FrameEditorLogic.previewLayout(
                    container: proxy.size,
                    imageWidth: originalImageWidth,
                    imageHeight: originalImageHeight
                )
                let scale = layout.scale
                let imageSize = layout.imageSize
                let origin = layout.origin
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.92)
                    if let nsImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: imageSize.width, height: imageSize.height)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    }
                    ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                        let active = selectedFrameIndex == index
                        Rectangle().stroke(active ? Color.orange : Color.red, lineWidth: active ? 3 : 2)
                        .background(Color.clear.contentShape(Rectangle()))
                        .overlay(alignment: .bottomTrailing) {
                            if active {
                                Rectangle().fill(Color.orange).frame(width: 14, height: 14)
                                    .gesture(DragGesture().onChanged { _ in
                                        if resizeIndex == nil { resizeIndex = index; resizeStart = frames[index] }
                                    }.onEnded { value in
                                        guard resizeIndex == index, let start = resizeStart else { return }
                                        var copy = frames
                                        copy[index] = FrameEditorLogic.resizedFromBottomRight(
                                            start,
                                            deltaWidth: Int(value.translation.width / scale),
                                            deltaHeight: Int(value.translation.height / scale),
                                            imageWidth: originalImageWidth,
                                            imageHeight: originalImageHeight
                                        )
                                        commit(copy); resizeIndex = nil; resizeStart = nil
                                    })
                            }
                        }
                        .frame(width: CGFloat(frame.width) * scale, height: CGFloat(frame.height) * scale)
                        .position(x: origin.x + (CGFloat(frame.x) + CGFloat(frame.width) / 2) * scale + (dragIndex == index ? translation.width : 0),
                                  y: origin.y + (CGFloat(frame.y) + CGFloat(frame.height) / 2) * scale + (dragIndex == index ? translation.height : 0))
                        .gesture(DragGesture().updating($translation) { value, state, _ in state = value.translation }
                            .onChanged { _ in if dragIndex == nil { dragIndex = index; dragStart = frames[index]; selectedFrameIndex = index } }
                            .onEnded { value in
                                guard let start = dragStart else { return }
                                var copy = frames
                                copy[index] = FrameEditorLogic.moved(
                                    start,
                                    deltaX: Int(value.translation.width / scale),
                                    deltaY: Int(value.translation.height / scale),
                                    imageWidth: originalImageWidth,
                                    imageHeight: originalImageHeight
                                )
                                commit(copy); dragIndex = nil; dragStart = nil
                            })
                        .onTapGesture { selectedFrameIndex = index }
                        Text("\(index + 1)").font(.caption.bold()).foregroundColor(.white)
                            .position(x: origin.x + CGFloat(frame.x) * scale + 12, y: origin.y + CGFloat(frame.y) * scale + 10)
                    }
                }
                .clipped()
            }
            .clipped()
            Divider()
            HStack(spacing: 8) {
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(history.undo.isEmpty)
                Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(history.redo.isEmpty)
                Divider().frame(height: 18)
                Button { addFrame() } label: { Image(systemName: "plus.rectangle") }
                Button { deleteSelected() } label: { Image(systemName: "trash") }.disabled(selectedFrameIndex == nil)
                Button { commit(FrameEditorLogic.spatiallyOrdered(frames)) } label: { Image(systemName: "list.number") }
                    .help(locale.text("reorder.frames"))
                Spacer()
                if !FrameEditorLogic.issues(in: frames, imageWidth: originalImageWidth, imageHeight: originalImageHeight).isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .help(locale.text("frame.geometry.warning"))
                }
                Button { commit(plan.automaticFrames) } label: { Image(systemName: "arrow.counterclockwise") }
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(.bar)
        }
        .onAppear { frames = plan.detectedFrames }
        .onChange(of: plan.detectedFrames) { _, value in if dragIndex == nil { frames = value } }
    }

    private func commit(_ newFrames: [FilmFrame]) {
        let normalized = FrameEditorLogic.normalized(newFrames)
        guard normalized != frames else { return }; history.undo.append(frames); history.redo.removeAll(); frames = normalized; onFramesChanged(normalized)
    }
    private func undo() { guard let previous = history.undo.popLast() else { return }; history.redo.append(frames); frames = previous; onFramesChanged(previous) }
    private func redo() { guard let next = history.redo.popLast() else { return }; history.undo.append(frames); frames = next; onFramesChanged(next) }
    private func deleteSelected() { guard let selectedFrameIndex else { return }; var copy = frames; copy.remove(at: selectedFrameIndex); self.selectedFrameIndex = nil; commit(copy) }
    private func addFrame() {
        commit(frames + [FrameEditorLogic.defaultFrame(
            existing: frames,
            imageWidth: originalImageWidth,
            imageHeight: originalImageHeight
        )])
    }
}

struct SuggestField: View {
    @Binding var text: String
    let suggestions: [String]
    var body: some View {
        HStack(spacing: 2) {
            TextField("", text: $text).textFieldStyle(.roundedBorder)
            if !suggestions.isEmpty { Menu { ForEach(suggestions, id: \.self) { value in Button(value) { text = value } } } label: { Image(systemName: "chevron.down") }.menuStyle(.borderlessButton).frame(width: 18) }
        }
    }
}
