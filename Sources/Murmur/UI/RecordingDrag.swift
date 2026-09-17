import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Makes its content a drag source for one recording.
///
/// SwiftUI's `.onDrag` with a file item provider puts a file URL on the pasteboard that
/// other sandboxed apps can't read. This goes through AppKit; see `RecordingWriter`
/// for what is offered instead.
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

/// What lands on the drag pasteboard for one recording: the raw bytes, then a file
/// promise. Deliberately no `public.file-url`. The recording lives inside this app's
/// sandbox container, and a Catalyst app such as WhatsApp takes the URL first, can't
/// read the path, and shows a 0 B file. With a promise the receiver hands us a folder
/// it can read and we write the file there ourselves, the way Photos and Mail do.
final class RecordingWriter: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    private let source: URL
    private let name: String
    private let bytes: Data?
    private let queue: OperationQueue = {
        let q = OperationQueue(); q.qualityOfService = .userInitiated; return q
    }()

    init(url: URL, fileName: String) {
        source = url
        name = fileName
        bytes = try? Data(contentsOf: url)
        super.init()
        fileType = UTType.m4a.identifier
        delegate = self
    }

    private static let audioType = NSPasteboard.PasteboardType(UTType.m4a.identifier)

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        if bytes != nil { types.insert(Self.audioType, at: 0) }
        return types
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == Self.audioType ? [] : super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == Self.audioType ? bytes : super.pasteboardPropertyList(forType: type)
    }

    // MARK: NSFilePromiseProviderDelegate

    func filePromiseProvider(_ p: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        name
    }

    func filePromiseProvider(_ p: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        do {
            try FileManager.default.copyItem(at: source, to: url)
            completionHandler(nil)
        } catch {
            Log.d("file promise failed: \(error)")
            completionHandler(error)
        }
    }

    func operationQueue(for p: NSFilePromiseProvider) -> OperationQueue { queue }
}

extension UTType {
    static let m4a = UTType("com.apple.m4a-audio") ?? .mpeg4Audio
}
