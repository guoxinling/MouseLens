import AppKit
import Foundation

struct NormalizedPoint: Codable, Hashable, Sendable {
    let x: Double
    let y: Double

    static let center = NormalizedPoint(x: 0.5, y: 0.5)

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

enum PointerEventType: String, Codable {
    case move
    case click
    case scroll
}

struct PointerEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: TimeInterval
    let location: NormalizedPoint
    let type: PointerEventType

    init(id: UUID = UUID(), timestamp: TimeInterval, location: NormalizedPoint, type: PointerEventType) {
        self.id = id
        self.timestamp = timestamp
        self.location = location
        self.type = type
    }
}

final class PointerEventStore {
    private var origin: Date?
    private var pausedAt: Date?
    private var accumulatedPausedDuration: TimeInterval = 0
    private var events: [PointerEvent] = []
    private let lock = NSLock()

    func reset() {
        lock.lock()
        origin = Date()
        pausedAt = nil
        accumulatedPausedDuration = 0
        events = []
        lock.unlock()
    }

    func pause() {
        lock.lock()
        defer { lock.unlock() }

        if origin == nil {
            origin = Date()
        }

        guard pausedAt == nil else { return }
        pausedAt = Date()
    }

    func resume() {
        lock.lock()
        defer { lock.unlock() }

        guard let pausedAt else { return }
        accumulatedPausedDuration += max(0, Date().timeIntervalSince(pausedAt))
        self.pausedAt = nil
    }

    func append(location: NormalizedPoint, type: PointerEventType) {
        lock.lock()
        defer { lock.unlock() }
        if origin == nil {
            origin = Date()
        }
        guard pausedAt == nil else { return }

        let base = origin ?? Date()
        let timestamp = max(0, Date().timeIntervalSince(base) - accumulatedPausedDuration)
        events.append(PointerEvent(timestamp: timestamp, location: location, type: type))
    }

    func snapshot() -> [PointerEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

@MainActor
final class EventTapMonitor {
    private let store: PointerEventStore
    private var monitors: [Any] = []

    init(store: PointerEventStore) {
        self.store = store
    }

    func start() {
        _ = stop()
        store.reset()

        let masks: [(NSEvent.EventTypeMask, PointerEventType)] = [
            (.mouseMoved, .move),
            (.leftMouseDragged, .move),
            (.rightMouseDragged, .move),
            (.leftMouseDown, .click),
            (.rightMouseDown, .click),
            (.scrollWheel, .scroll)
        ]

        for (mask, type) in masks {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
                self?.record(event: event, as: type)
            }) {
                monitors.append(monitor)
            }
        }
    }

    func stop() -> [PointerEvent] {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        return store.snapshot()
    }

    func pause() {
        store.pause()
    }

    func resume() {
        store.resume()
    }

    private func record(event: NSEvent, as type: PointerEventType) {
        let bounds = Self.activeScreenBounds()
        guard let normalized = Self.normalizedLocation(for: NSEvent.mouseLocation, in: bounds) else { return }
        store.append(location: normalized, type: type)
    }

    static func activeScreenBounds() -> CGRect {
        NSScreen.screens.reduce(CGRect.null) { partialResult, screen in
            partialResult.union(screen.frame)
        }
    }

    static func normalizedLocation(for globalLocation: CGPoint, in bounds: CGRect) -> NormalizedPoint? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        return NormalizedPoint(
            x: ((globalLocation.x - bounds.minX) / bounds.width).clamped(to: 0...1),
            y: 1 - ((globalLocation.y - bounds.minY) / bounds.height).clamped(to: 0...1)
        )
    }
}
