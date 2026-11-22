import SwiftUI
import BoostGaugeKit

@main
struct BoostGaugeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let context = AppDelegate.context

    // Scenes can't be generated in a loop. Each is a fixed slot, `Item-<index>` to macOS, that shows
    // whichever item belongs at its place in the menu bar.
    var body: some Scene {
        ItemScene(slot: 0, context: context)
        ItemScene(slot: 1, context: context)
        ItemScene(slot: 2, context: context)
        ItemScene(slot: 3, context: context)
        ItemScene(slot: 4, context: context)
        ItemScene(slot: 5, context: context)
        ItemScene(slot: 6, context: context)
        ItemScene(slot: 7, context: context)
        Settings { context.settingsView }
    }
}

/// One menu bar slot. It stays out of the menu bar until a track registers its item and the user shows it.
struct ItemScene: Scene {
    let slot: Int
    let context: AppContext

    var body: some Scene {
        // Read here, not only inside the Binding, so the scene re-evaluates when Settings or the slots change.
        let item = context.scheduler.item(context.slots.item(inSlot: slot))
        let inserted = item != nil && !RenderMode.isActive && context.slots.isInserted(slot)
        MenuBarExtra(isInserted: Binding(
            get: { inserted },
            // macOS sets this false when the user takes the item out of the menu bar.
            set: { if item != nil { context.slots.systemSetInserted(slot: slot, $0) } }
        )) {
            if let item {
                // A reorder can hand an open slot a different item; a new identity closes the old one's panel cleanly.
                item.panel
                    .onAppear { item.panelDidOpen() }
                    .onDisappear { item.panelDidClose() }
                    .id(context.slots.item(inSlot: slot))
            }
        } label: {
            item?.label ?? AnyView(EmptyView())
        }
        .menuBarExtraStyle(.window)
    }
}
