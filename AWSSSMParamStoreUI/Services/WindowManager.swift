import AppKit
import Combine

class WindowManager: ObservableObject {
    static let shared = WindowManager()
    
    private var isHandlingTabRequest = false
    private var sourceWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe when a new window becomes key (which happens when a new window is opened)
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] notification in
                self?.handleNewWindow(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleNewWindow(_ notification: Notification) {
        guard isHandlingTabRequest,
              let newWindow = notification.object as? NSWindow,
              let sourceWindow = sourceWindow,
              newWindow !== sourceWindow else {
            return
        }
        
        // Found the new window, merge it
        sourceWindow.addTabbedWindow(newWindow, ordered: .above)
        
        // Reset state
        isHandlingTabRequest = false
        self.sourceWindow = nil
    }
    
    func openNewTab() {
        guard let currentWindow = NSApp.keyWindow else { return }
        
        isHandlingTabRequest = true
        sourceWindow = currentWindow
        
        // Send the action to create a new window
        // We rely on the observer to catch it and merge it
        NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
        
        // Fallback reset in case window creation fails or takes too long
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isHandlingTabRequest = false
            self?.sourceWindow = nil
        }
    }
    
    func openNewWindow() {
        // Just standard behavior
        NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
    }
}

