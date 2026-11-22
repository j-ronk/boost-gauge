import Observation

/// Calls `onHide` whenever `id` is hidden (Settings toggle or Cmd-drag out of the menu bar).
/// Items use it to drop delta baselines and history, so the first reading after re-showing isn't
/// an average across the whole hidden span.
@MainActor final class ShownWatcher {
    private let settings: AppSettings
    private let id: ItemID
    private let onHide: () -> Void

    init(settings: AppSettings, id: ItemID, onHide: @escaping () -> Void) {
        self.settings = settings
        self.id = id
        self.onHide = onHide
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = settings.isShown(id)
        } onChange: { [weak self] in
            // onChange fires before the new value is stored, so read it on the next main-actor turn.
            Task { @MainActor in
                guard let self else { return }
                if !self.settings.isShown(self.id) { self.onHide() }
                self.observe()
            }
        }
    }
}
