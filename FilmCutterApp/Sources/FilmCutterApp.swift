import SwiftUI

@main
struct FilmCutterApp: App {
    @StateObject private var bridge = PythonBridge()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bridge)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About FilmCutter") {
                    AboutWindowManager.shared.show()
                }
            }
        }
    }
}

@MainActor
private final class AboutWindowManager {
    static let shared = AboutWindowManager()
    private var controller: NSWindowController?

    func show() {
        if let existing = controller?.window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About FilmCutter"
        window.isReleasedWhenClosed = false
        window.center()

        let view = NSHostingView(rootView: AboutView())
        view.frame = NSRect(x: 0, y: 0, width: 380, height: 220)
        window.contentView = view

        // Retain the controller. A local-only controller can be released as
        // soon as this method returns, causing the About window to disappear.
        let newController = NSWindowController(window: window)
        controller = newController
        newController.showWindow(nil)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            if let logo = NSImage(contentsOf: logoPath()) {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
            }

            Text("FilmCutter")
                .font(.title.weight(.bold))

            Text("Version 1.0")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Cut scanned film strips into individual frames.\nSupports TIFF files from Hasselblad X5 and other scanners.")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Made by Warsaw 华沙")
                .font(.callout)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 380, height: 220)
    }

    private func logoPath() -> URL {
        Bundle.module.url(forResource: "logo", withExtension: "svg")
            ?? URL(fileURLWithPath: "")
    }
}
