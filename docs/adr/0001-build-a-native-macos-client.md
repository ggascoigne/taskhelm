# Build a native macOS client

The Mac client will be built in Swift, using SwiftUI for ordinary interface construction and targeted AppKit integration for global shortcuts, transient window behavior, focus management, menu-bar lifecycle, and Accessibility APIs. Native implementation is preferred over Electron or Tauri because Quick Capture depends on responsive, reliable integration with macOS, and that benefit outweighs reuse of web-platform expertise.
