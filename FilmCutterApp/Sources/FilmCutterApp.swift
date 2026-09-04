import SwiftUI

@main
struct FilmCutterApp: App {
    @StateObject private var bridge = PythonBridge()
    @StateObject private var locale = LocalizationStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bridge)
                .environmentObject(locale)
                .frame(minWidth: 900, minHeight: 640)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(locale.text("about")) {
                    AboutWindowManager.shared.show(locale: locale)
                }
            }
            CommandGroup(after: .help) {
                Link(locale.text("source"), destination: URL(string: "https://github.com/WarsawYing/FilmCutter")!)
            }
        }
    }
}

@MainActor
private final class AboutWindowManager {
    static let shared = AboutWindowManager()
    private var controller: NSWindowController?

    func show(locale: LocalizationStore) {
        if let existing = controller?.window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = locale.text("about")
        window.isReleasedWhenClosed = false
        window.center()

        let view = NSHostingView(rootView: AboutView().environmentObject(locale))
        view.frame = NSRect(x: 0, y: 0, width: 430, height: 300)
        window.contentView = view

        // Retain the controller. A local-only controller can be released as
        // soon as this method returns, causing the About window to disappear.
        let newController = NSWindowController(window: window)
        controller = newController
        newController.showWindow(nil)
    }
}

struct AboutView: View {
    @EnvironmentObject private var locale: LocalizationStore
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack.fill")
                .font(.system(size: 54)).foregroundColor(.accentColor)

            Text("FilmCutter")
                .font(.title.weight(.bold))

            Text("Version 1.1")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(locale.text("about.description"))
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Copyright © 2026 Warsawying")
                .font(.callout)
                .padding(.top, 4)
            HStack(spacing: 12) {
                Link(locale.text("source"), destination: URL(string: "https://github.com/WarsawYing/FilmCutter")!)
                Link(locale.text("license"), destination: URL(string: "https://github.com/WarsawYing/FilmCutter/blob/main/LICENSE")!)
            }
            HStack(spacing: 12) {
                Link(locale.text("third.party"), destination: URL(string: "https://github.com/WarsawYing/FilmCutter/blob/main/THIRD_PARTY_NOTICES.md")!)
                Link(locale.text("contributors"), destination: URL(string: "https://github.com/WarsawYing/FilmCutter/blob/main/CONTRIBUTORS.md")!)
            }
            .font(.caption)
        }
        .padding(24)
        .frame(width: 430, height: 300)
    }
}
