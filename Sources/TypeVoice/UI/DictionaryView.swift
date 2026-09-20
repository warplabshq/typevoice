import SwiftUI

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
