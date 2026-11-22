import Foundation
import Observation

/// One shared menu bar clock, so hidden items cost nothing and every label updates on the same beat.
@MainActor public final class Scheduler {
    public private(set) var items: [any BoostGaugeItem] = []
    private let settings: AppSettings
    private var loop: Task<Void, Never>?
    private var shownAtLastTick: Set<ItemID> = []

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public func register(_ item: any BoostGaugeItem) {
        items.append(item)
    }

    public func item(_ id: ItemID) -> (any BoostGaugeItem)? {
        items.first { $0.id == id }
    }

    /// Ticks shown items only. Test seam for the loop in `start()`.
    public func fire(now: Date) {
        for item in items where settings.isShown(item.id) {
            item.tick(now: now)
        }
        shownAtLastTick = Set(items.map(\.id).filter(settings.isShown))
    }

    /// An item switched on in Settings would otherwise show a blank label for up to a whole interval.
    private func tickNewlyShown(now: Date) {
        let shown = Set(items.map(\.id).filter(settings.isShown))
        for item in items where shown.contains(item.id) && !shownAtLastTick.contains(item.id) {
            item.tick(now: now)
        }
        shownAtLastTick = shown
    }

    private func watchShown() {
        guard loop != nil else { return }
        withObservationTracking {
            for item in items { _ = settings.isShown(item.id) }
        } onChange: { [weak self] in
            // onChange fires before the new value is stored, so act on the next main-actor turn.
            Task { @MainActor in
                self?.tickNewlyShown(now: .now)
                self?.watchShown()
            }
        }
    }

    public func start() {
        guard loop == nil else { return }
        fire(now: .now)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                // Read each pass so a Settings change applies from the next tick without a restart.
                guard let seconds = self?.settings.refreshSeconds else { return }
                // Tolerance lets the system coalesce our wake-ups with others, which is most of the energy saving.
                try? await Task.sleep(for: .seconds(seconds), tolerance: .milliseconds(seconds * 200))
                guard let self, !Task.isCancelled else { return }
                self.fire(now: .now)
            }
        }
        watchShown()
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }
}
