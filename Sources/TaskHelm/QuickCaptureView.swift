import SwiftUI

struct QuickCaptureView: View {
    @ObservedObject var model: QuickCaptureViewModel
    var onShowTaskBrowser: () -> Void = {}
    var onNoteEditorExpansionChanged: (Bool) -> Void = { _ in }

    @State private var isNoteEditorExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TaskHelm — New Task")
                    .font(.headline)

                Spacer()

                Button(action: onShowTaskBrowser) {
                    Label("Browse Tasks", systemImage: "macwindow")
                }
                .help("Browse Tasks (⌘B)")
            }

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)

                TextField("What needs to be done?", text: $model.draft.description)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit {
                        guard !isNoteEditorExpanded else { return }
                        submit()
                    }

                if model.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Divider()

            HStack(spacing: 10) {
                AutocompleteTextField(
                    text: $model.draft.project,
                    prompt: "Project",
                    suggestions: model.metadata.projects
                )
                .frame(width: 130, height: 22)

                TagTokenField(tags: $model.draft.tags, suggestions: model.metadata.tags)
                    .frame(width: 150, height: 22)

                PriorityPicker(selection: $model.draft.priority, priorities: model.metadata.priorities)
                .frame(width: 90)

                DueDateField(due: $model.draft.due, textFieldWidth: 100, onSubmit: submit)
            }

            if let context = model.metadata.context {
                Label("Context: \(context)", systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    isNoteEditorExpanded.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isNoteEditorExpanded ? "chevron.down" : "chevron.right")
                            .imageScale(.small)
                            .frame(width: 10)
                        Text("Add Note")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add Note")
                .accessibilityValue(isNoteEditorExpanded ? "Expanded" : "Collapsed")

                if isNoteEditorExpanded {
                VStack(alignment: .trailing, spacing: 8) {
                    TextEditor(text: $model.draft.note)
                        .scrollContentBackground(.hidden)
                        .frame(height: 96)
                        .padding(4)
                        .accessibilityLabel("New task note")
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.separator, lineWidth: 1)
                        }

                    Button("Add Task", action: submit)
                        .disabled(!model.draft.isValid || model.isSubmitting)
                }
                .padding(.top, 6)
                }
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(18)
        .frame(width: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand(perform: model.cancel)
        .onChange(of: isNoteEditorExpanded) { _, isExpanded in
            onNoteEditorExpansionChanged(isExpanded)
        }
    }

    private func submit() {
        Task { await model.submit() }
    }
}
