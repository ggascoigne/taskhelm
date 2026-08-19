import AppKit
import SwiftUI

extension NSUserInterfaceItemIdentifier {
    static let taskBrowserWindow = NSUserInterfaceItemIdentifier("task-browser")
}

enum TaskBrowserWindowPlacement {
    static func browserWindow(in windows: [NSWindow] = NSApp.windows) -> NSWindow? {
        windows.first { window in
            isBrowserWindow(window) && (window.isVisible || window.isMiniaturized)
        }
    }

    static func isBrowserWindow(_ window: NSWindow) -> Bool {
        isBrowserWindow(identifier: window.identifier)
    }

    static func isBrowserWindow(identifier: NSUserInterfaceItemIdentifier?) -> Bool {
        identifier == .taskBrowserWindow
    }

    static func moveToActiveDesktop(_ window: NSWindow) {
        window.collectionBehavior = activeDesktopBehavior(from: window.collectionBehavior)
        window.orderFrontRegardless()
    }

    static func activeDesktopBehavior(
        from behavior: NSWindow.CollectionBehavior
    ) -> NSWindow.CollectionBehavior {
        var updated = behavior
        updated.remove(.canJoinAllSpaces)
        updated.insert(.moveToActiveSpace)
        return updated
    }
}

struct TaskBrowserWindowMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        MarkerView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.window?.identifier = .taskBrowserWindow
    }

    private final class MarkerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.identifier = .taskBrowserWindow
        }
    }
}
