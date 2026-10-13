import ApplicationServices
import CoreGraphics
import Foundation

public struct ScrollPermissions: Equatable, Sendable {
    public let accessibilityGranted: Bool
    public let inputMonitoringGranted: Bool
}

public enum ScrollStartResult: Equatable, Sendable {
    case started
    case accessibilityRequired
    case eventTapUnavailable
}

/// Owns a filtering tap installed on the main run loop. No events are reposted,
/// so an event can never be reversed twice by this service.
@MainActor
public final class ScrollService {
    private var session: ScrollTapSession?

    public init() {}

    public static var permissions: ScrollPermissions {
        .init(
            accessibilityGranted: AXIsProcessTrusted(),
            inputMonitoringGranted: CGPreflightListenEventAccess()
        )
    }

    @discardableResult
    public static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    public var isRunning: Bool {
        session?.isRunning ?? false
    }

    @discardableResult
    public func start() -> ScrollStartResult {
        guard AXIsProcessTrusted() else {
            stop()
            return .accessibilityRequired
        }
        if isRunning { return .started }
        stop()
        guard let newSession = ScrollTapSession() else { return .eventTapUnavailable }
        session = newSession
        return .started
    }

    public func stop() {
        session = nil
    }
}

/// Callback state is independent of the service. It stays alive until the tap
/// has been removed and invalidated on its run loop, including during deinit.
private final class ScrollTapContext {
    var tap: CFMachPort?

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        switch type {
        case .tapDisabledByTimeout:
            // The window server disables slow taps. The callback does no UI,
            // dispatching, logging, or permission checks during normal scrolling.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .tapDisabledByUserInput:
            // Leave this disabled. The app can inspect isRunning and explicitly
            // restart after checking permission again.
            break
        case .scrollWheel:
            ScrollTransformer.reverseMouseEvent(event)
        default:
            break
        }
        return .passUnretained(event)
    }
}

private final class ScrollTapSession {
    let context: ScrollTapContext
    let tap: CFMachPort
    let source: CFRunLoopSource

    var isRunning: Bool {
        CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
    }

    init?() {
        dispatchPrecondition(condition: .onQueue(.main))
        let context = ScrollTapContext()
        let mask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return .passUnretained(event) }
                let context = Unmanaged<ScrollTapContext>.fromOpaque(userInfo).takeUnretainedValue()
                return context.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        ) else { return nil }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return nil
        }
        self.context = context
        self.tap = tap
        self.source = source
        context.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    deinit {
        // @MainActor normally releases this on the main thread. If its final
        // owner is released elsewhere, retain all callback resources until the
        // main run loop can tear them down without racing a callback.
        let context = context
        let tap = tap
        let source = source
        let cleanup = {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
            CFMachPortInvalidate(tap)
            context.tap = nil
        }
        if Thread.isMainThread {
            cleanup()
        } else {
            DispatchQueue.main.async(execute: cleanup)
        }
    }
}
