import AppKit

/// Menu bar labels must hand back the same NSImage for the same content. The MenuBarExtra host treats a new
/// image instance as a change and schedules another label update, so drawing inside `body` spun forever.
@MainActor final class LabelImageCache<Key: Hashable> {
    private let limit: Int
    private var images: [Key: NSImage] = [:]
    // Least recently used first. Short enough (a few dozen keys) that linear removal is cheaper than a list.
    private var order: [Key] = []

    init(limit: Int) {
        self.limit = limit
    }

    var count: Int { images.count }

    func image(for key: Key, draw: () -> NSImage) -> NSImage {
        if let image = images[key] {
            if order.last != key, let i = order.firstIndex(of: key) {
                order.remove(at: i)
                order.append(key)
            }
            return image
        }
        let image = draw()
        images[key] = image
        order.append(key)
        if order.count > limit { images[order.removeFirst()] = nil }
        return image
    }
}
