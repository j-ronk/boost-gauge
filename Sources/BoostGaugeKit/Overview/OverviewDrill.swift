import AppKit
import SwiftUI

extension OverviewMetric {
    /// The item whose own panel a click on the metric opens.
    var item: ItemID {
        switch self {
        case .cpu: .cpu
        case .gpu: .gpu
        case .memory: .memory
        case .disk: .disk
        case .cpuTemp, .gpuTemp, .batteryTemp, .hottest: .temps
        case .battery: .battery
        case .systemPower: .power
        case .network: .network
        }
    }
}

extension OverviewMetric.Group {
    /// Usage spans four items, so its heading opens nothing.
    var item: ItemID? {
        switch self {
        case .usage: nil
        case .temperatures: .temps
        case .power: .power
        }
    }
}

@MainActor enum OverviewDrillText {
    static func accessibilityLabel(_ id: ItemID) -> String { "Show \(SettingsModel.title(id)) details" }
}

/// What the live panel needs from its item: the other items' panels, and word of what's on screen so only that samples.
@MainActor protocol OverviewHost: AnyObject {
    func panel(for id: ItemID) -> AnyView?
    func detailOpened(_ id: ItemID)
    func detailClosed(_ id: ItemID)
    /// The List's open CPU row lists processes; CPU's process baseline runs only while it does.
    func processesShown(_ shown: Bool)
    func sampleProcesses() async
}

/// Which item's panel stands in for the Overview, one level deep, as in Control Centre. One per open panel, so the
/// Settings preview never follows the menu bar's drill.
@MainActor @Observable final class OverviewNavigator {
    private(set) var shown: ItemID?
    @ObservationIgnored private weak var host: OverviewHost?

    init(host: OverviewHost?) {
        self.host = host
    }

    func open(_ id: ItemID) {
        guard id != shown, id != .overview else { return }
        let previous = shown
        shown = id
        host?.detailOpened(id)
        if let previous { host?.detailClosed(previous) }
    }

    /// Back, Esc, ⌘[, and the popover closing.
    func back() {
        guard let id = shown else { return }
        shown = nil
        host?.detailClosed(id)
    }
}

/// The drilled-in panel: a back button to the Overview above the item's own panel, unchanged.
struct OverviewDetail: View {
    let id: ItemID
    let panel: AnyView
    var back: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                back?()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").fontWeight(.semibold)
                    Text("Overview")
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .keyboardShortcut("[", modifiers: .command)
            .accessibilityLabel("Back to Overview")
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, -4)
            // Nothing in the item's panel holds focus, so Esc comes as the window's cancel action.
            .background {
                Button("Back", action: { back?() })
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            panel
        }
        .frame(width: 300, alignment: .leading)
    }
}

extension EnvironmentValues {
    /// Set by the Settings preview, which draws a panel without letting it take focus or keys.
    @Entry var isPanelPreview = false
}

/// Slides a whole view by a fraction of its width. `.move` pushes its offset down onto the views present when the
/// transition starts, so rows an item's panel adds mid-slide (its processes, after a `top` run) landed in place
/// and showed up stationary. A geometry effect offsets the view as one piece, rows added later included.
struct DrillSlide: GeometryEffect {
    /// -1 is a full width to the left, 1 to the right, 0 in place.
    var fraction: CGFloat

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: fraction * size.width, y: 0))
    }
}

extension AnyTransition {
    /// In from `edge` and back out to it, as Control Centre's modules do.
    static func drillSlide(_ edge: HorizontalEdge) -> AnyTransition {
        .modifier(active: DrillSlide(fraction: edge == .leading ? -1 : 1), identity: DrillSlide(fraction: 0))
    }
}
