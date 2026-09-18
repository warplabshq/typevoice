import AppKit
import SwiftUI

/// Makes its content a drag source for one recording.
///
/// SwiftUI's `.onDrag` with a file item provider offers bytes, a promise and a temp
/// copy that vanishes when the drag ends; WhatsApp ends up with a 0 KB file. This goes
/// through AppKit and offers one thing: a file URL. See `RecordingWriter`.
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

        guard let writer = RecordingWriter(url: url, fileName: fileName) else { return }
        let item = NSDraggingItem(pasteboardWriter: writer)
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

/// What lands on the drag pasteboard for one recording: a file URL, and nothing else.
///
/// Measured against a sandboxed Catalyst receiver (what WhatsApp is): it loads the item
/// "in place" and reads it later. Given a file URL it gets the real file, readable
/// afterwards thanks to the sandbox extension the pasteboard attaches. Given audio bytes
/// or a file promise, UIKit prefers those, hands over a temp copy named
/// `.com.apple.Foundation.NSItemProvider.XXXX.m4a`, and deletes it before the app copies
/// it, which is the 0 KB file. So this is exactly what Finder puts on the pasteboard.
final class RecordingWriter: NSObject, NSPasteboardWriting {
    private let linkURL: URL

    init?(url: URL, fileName: String) {
        guard let link = RecordingStore.dragLink(for: url, named: fileName) else { return nil }
        linkURL = link
        super.init()
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        (linkURL as NSURL).writableTypes(for: pasteboard)
    }

    func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        (linkURL as NSURL).writingOptions(forType: type, pasteboard: pasteboard)
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        (linkURL as NSURL).pasteboardPropertyList(forType: type)
    }
}
