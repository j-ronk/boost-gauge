import SwiftUI

/// A segmented control drawn as a capsule track with a raised thumb under the selection. The thumb can take a
/// colour per option (Low Power's yellow). VoiceOver sees a native segmented picker; each segment is a button,
/// so it also works from the keyboard.
struct CapsulePicker<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        var symbol: String?
        /// Thumb colour when this option is selected; nil keeps the neutral thumb.
        var tint: Color?
    }

    let title: String
    @Binding var selection: Value?
    let options: [Option]
    var height: CGFloat = 24
    /// Equal-width segments across the row, or segments that hug their titles.
    var fillsWidth = true

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme
    @Namespace private var thumbSpace

    static var inset: CGFloat { 2 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                segment(options[i])
            }
        }
        .padding(Self.inset)
        .frame(height: height)
        .fixedSize(horizontal: !fillsWidth, vertical: false)
        .background(Capsule().fill(.primary.opacity(scheme == .dark ? 0.1 : 0.08)))
        .animation(.snappy(duration: 0.2), value: selection)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityRepresentation {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { i in
                    Text(options[i].title).tag(Optional(options[i].value))
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func segment(_ option: Option) -> some View {
        let selected = option.value == selection
        let tinted = selected && option.tint != nil
        return Button {
            selection = option.value
        } label: {
            HStack(spacing: 4) {
                if let symbol = option.symbol {
                    Image(systemName: symbol)
                        .imageScale(.small)
                        .foregroundStyle(tinted ? AnyShapeStyle(.black.opacity(0.85)) : AnyShapeStyle(.secondary))
                }
                Text(option.title)
                    .lineLimit(1)
                    .foregroundStyle(tinted ? AnyShapeStyle(.black.opacity(0.85)) : AnyShapeStyle(.primary))
            }
            .padding(.horizontal, fillsWidth ? 4 : 10)
            .frame(maxWidth: fillsWidth ? .infinity : nil, maxHeight: .infinity)
            .background {
                if selected {
                    Capsule()
                        .fill(option.tint ?? thumbColor)
                        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.16), radius: 1, y: 0.5)
                        .overlay(Capsule().strokeBorder(.black.opacity(scheme == .dark ? 0 : 0.06), lineWidth: 0.5))
                        .matchedGeometryEffect(id: "thumb", in: thumbSpace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var thumbColor: Color {
        scheme == .dark ? Color(white: 0.37) : .white
    }
}
