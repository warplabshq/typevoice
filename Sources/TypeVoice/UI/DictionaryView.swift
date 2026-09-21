import SwiftUI
import UniformTypeIdentifiers

struct DictionaryView: View {
    let dictionary: DictionaryStore
    @State private var draft = ""
    @State private var selection: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Add a name or a phrase, spelled the way you want it", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($focused)
                    .onSubmit(add)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            if dictionary.terms.isEmpty {
                ContentUnavailableView {
                    Label("Your words, your spelling", systemImage: "character.book.closed")
                } description: {
                    Text("Product names, people, jargon. \(Brand.name) fixes anything that sounds like them.")
                }
                .frame(maxHeight: .infinity)
            } else {
                List(dictionary.terms, id: \.self, selection: $selection) { term in
                    HStack {
                        Text(term).font(.body)
                        Spacer()
                        Button(role: .destructive) { dictionary.remove(term) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Remove")
                    }
                    .padding(.vertical, 2)
                    .tag(term)
                }
                .listStyle(.inset)
                .onDeleteCommand { if let s = selection { dictionary.remove(s); selection = nil } }
            }

            Divider()
            PacksSection()
            Divider()
            Text("Applied after recognition, on this Mac. Recognition itself stays unchanged, so the model never sees your list.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .onAppear { focused = true }
    }

    private func add() {
        if dictionary.add(draft) { draft = "" }
    }
}

/// Word packs: thousands of spellings the model tends to mangle, shipped inside the app, each
/// a switch. Packs only fire where the model was unsure; your own words above always win.
private struct PacksSection: View {
    @State private var packs: [Packs.Pack] = Packs.all()
    @State private var enabled = Set(Prefs.packs)
    @State private var importError: String?
    @State private var showGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Packs").font(.headline)
                Spacer()
                Button("Import a list…") { showGuide = true }.controlSize(.small)
                    .popover(isPresented: $showGuide, arrowEdge: .bottom) { guide }
            }
            ForEach(packs) { pack in
                HStack(spacing: 10) {
                    Text(pack.name)
                    Text("\(pack.count.formatted()) words").foregroundStyle(.secondary)
                    Spacer()
                    if !pack.builtIn {
                        Button(role: .destructive) { Packs.remove(pack); reload() } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove this list")
                    }
                    Toggle("", isOn: Binding(get: { enabled.contains(pack.id) }, set: { on in
                        Packs.setEnabled(pack, on); enabled = Set(Prefs.packs)
                    }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                .padding(.vertical, 2)
            }
            Text(footnote).font(.caption).foregroundStyle(.secondary)
            if let importError { Text(importError).font(.caption).foregroundStyle(.red) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// What a list looks like, shown before the file dialog so nobody has to guess.
    private var guide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Import a list").font(.headline)
            Text("A plain text file, one word or phrase per line, spelled exactly the way you want it typed. Blank lines and lines starting with # are ignored. The file's name becomes the pack's name.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("""
                # Team vocabulary
                Composio
                Higgsfield
                Harsh Govind
                Logs.so
                """)
                .font(.system(.callout, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            Text("Good for a team's product names, a project's jargon, or the names of everyone you write to. Share the file; each person imports it. Nothing leaves the Mac.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { showGuide = false }
                Button("Choose File…") { showGuide = false; importList() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 400)
    }

    private var footnote: String {
        "Developer tools is built from Homebrew, PyPI and Wikidata; Internet slang is hand-picked. Files inside the app, never fetched. A pack only steps in where the model was unsure of a word."
    }

    private func reload() { packs = Packs.all(); enabled = Set(Prefs.packs) }

    private func importList() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.message = "One word or phrase per line, spelled the way you want it typed."
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            do { try Packs.importFile(url); importError = nil } catch { importError = error.localizedDescription }
            reload()
        }
    }
}
