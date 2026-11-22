import SwiftUI

extension View {
    /// Panel-only polling: runs `action` now and then every `every` while the view is on screen.
    /// Tied to `.task`, so closing the panel cancels it and nothing polls in the background.
    public func refreshing(every interval: Duration, _ action: @escaping () async -> Void) -> some View {
        task {
            while !Task.isCancelled {
                await action()
                try? await Task.sleep(for: interval)
            }
        }
    }
}
