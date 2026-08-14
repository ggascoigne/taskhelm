import Foundation
import TWMacCore

@MainActor
final class QuickCaptureViewModel: ObservableObject {
    @Published var draft = QuickCaptureDraft()
    @Published var metadata = TaskwarriorMetadata(projects: [], tags: [], priorities: [], context: nil)
    @Published var errorMessage: String?
    @Published var isSubmitting = false

    private let client: any TaskwarriorServing
    private let onCancel: () -> Void
    private let onCreated: () -> Void

    init(
        client: any TaskwarriorServing,
        onCancel: @escaping () -> Void,
        onCreated: @escaping () -> Void
    ) {
        self.client = client
        self.onCancel = onCancel
        self.onCreated = onCreated
    }

    func prepare(description: String) {
        draft = QuickCaptureDraft(description: SelectedTextNormalizer.normalize(description))
        errorMessage = nil
        isSubmitting = false
    }

    func loadMetadata() async {
        do {
            metadata = try await client.metadata()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submit() async {
        guard draft.isValid, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await client.createTask(from: draft)
            NotificationCenter.default.post(name: .taskwarriorTaskCreated, object: nil)
            onCreated()
        } catch {
            errorMessage = error.localizedDescription
            isSubmitting = false
        }
    }

    func cancel() {
        onCancel()
    }
}
