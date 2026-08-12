import SwiftUI

struct QuickCaptureView: View {
    @ObservedObject var model: QuickCaptureViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.secondary)

                TextField("What needs to be done?", text: $model.draft.description)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit(submit)

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

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .padding(18)
        .frame(width: 660)
        .onExitCommand(perform: model.cancel)
    }

    private func submit() {
        Task { await model.submit() }
    }
}
