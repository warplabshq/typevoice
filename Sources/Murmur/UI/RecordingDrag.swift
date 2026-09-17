import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Makes its content a drag source for one recording.
///
/// SwiftUI's `.onDrag` with a file item provider leads with a file promise and a temp
/// copy that is deleted when the drag ends, which is how WhatsApp ended up with a 0 KB
/// file. This goes through AppKit and puts exactly what Finder puts on the pasteboard
/// (see `RecordingWriter`).
struct RecordingDrag<Content: View>: NSViewRepresentable {
    let url: URL
    let fileName: String
    var onHover: ((Bool) -> Void)? = nil
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> DragSourceView {
        let v = DragSourceView(hosting: NSHostingView(rootView: AnyView(content())))
        v.url = url; v.fileName = fileName; v.onHover = onHover
        return v
    }

    func updateNSView(_ v: DragSourceView, context: Context) {
        v.hosting.rootView = AnyView(content())
        v.url = url; v.fileName = fileName; v.onHover = onHover
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DragSourceView, context: Context) -> CGSize? {
        nsView.hosting.fittingSize
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    /// True while any recording drag is in flight, so the pill doesn't vanish mid-drag.
    @MainActor static var isDragging = false

    let hosting: NSHostingView<AnyView>
    var url: URL = URL(fileURLWithPath: "/")
    var fileName = "Voice note"
    var onHover: ((Bool) -> Void)?
    private var downAt: NSPoint?
    private var tracking: NSTrackingArea?

    init(hosting: NSHostingView<AnyView>) {
        self.hosting = hosting
        super.init(frame: .zero)
        hosting.sizingOptions = .intrinsicContentSize
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { hosting.intrinsicContentSize }

    // Mouse events come here, not to the hosted SwiftUI view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        downAt = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downAt else { return }
        let d = hypot(event.locationInWindow.x - downAt.x, event.locationInWindow.y - downAt.y)
        guard d > 4 else { return }
        self.downAt = nil

        let item = NSDraggingItem(pasteboardWriter: RecordingWriter(url: url, fileName: fileName))
        item.setDraggingFrame(bounds, contents: snapshot())
        DragSourceView.isDragging = true
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) { downAt = nil }

    private func snapshot() -> NSImage? {
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let img = NSImage(size: hosting.bounds.size)
        img.addRepresentation(rep)
        return img
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DragSourceView.isDragging = false
        onHover?(false)
    }
}

/// What lands on the drag pasteboard for one recording, in the same shape Finder uses:
/// a file URL first (a hard link carrying the friendly name, so the path outlives the
/// drag), then the raw bytes for apps that only take data. No file promise: Catalyst
/// apps such as WhatsApp don't fulfil promises from other apps and end up with 0 KB.
final class RecordingWriter: NSObject, NSPasteboardWriting {
    private let source: URL
    private let linkURL: URL?

    init(url: URL, fileName: String) {
        source = url
        linkURL = RecordingStore.dragLink(for: url, named: fileName)
        super.init()
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types: [NSPasteboard.PasteboardType] = []
        if linkURL != nil { types.append(.fileURL) }
        types.append(NSPasteboard.PasteboardType(UTType.m4a.identifier))
        return types
    }

    func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        // The URL is written up front (that's what carries the sandbox extension); bytes on demand.
        type == .fileURL ? [] : .promised
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .fileURL, let linkURL { return (linkURL as NSURL).pasteboardPropertyList(forType: type) }
        return try? Data(contentsOf: source)
    }
}

extension UTType {
    static let m4a = UTType("com.apple.m4a-audio") ?? .mpeg4Audio
}
