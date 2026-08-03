import AppKit
import SwiftUI
import TWMacCore

struct TaskBrowserRootView: View {
    @StateObject private var model: TaskBrowserViewModel

    init(settings: AppSettings) {
        _model = StateObject(
            wrappedValue: TaskBrowserViewModel(
                loadTasks: { query in
                    let client = TaskwarriorClient(
                        environment: settings.taskwarriorEnvironment,
                        runner: FoundationProcessRunner()
                    )
                    return try await client.tasks(matching: query)
                },
                loadMetadata: {
                    let client = TaskwarriorClient(
                        environment: settings.taskwarriorEnvironment,
                        runner: FoundationProcessRunner()
                    )
                    return try await client.metadata()
                },
                performMutation: { mutation in
                    let client = TaskwarriorClient(
                        environment: settings.taskwarriorEnvironment,
                        runner: FoundationProcessRunner()
                    )
                    return try await client.perform(mutation)
                },
                undoMutation: { receipt in
                    let client = TaskwarriorClient(
                        environment: settings.taskwarriorEnvironment,
                        runner: FoundationProcessRunner()
                    )
                    try await client.undo(receipt)
                }
            )
        )
    }

    var body: some View {
        TaskBrowserView(model: model)
    }
}

struct TaskBrowserView: View {
    @ObservedObject var model: TaskBrowserViewModel
    @State private var confirmsDelete = false

    var body: some View {
        NavigationSplitView {
            BrowserSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 280)
        } content: {
            taskList
                .navigationSplitViewColumnWidth(min: 560, ideal: 760)
        } detail: {
            TaskInspector(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 440)
        }
        .navigationTitle(model.view.title)
        .toolbar { browserToolbar }
        .focusedSceneValue(\.taskBrowserCommands, commandActions)
        .task {
            await model.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                if NSApp.windows.contains(where: { $0.title == "Task Browser" && $0.isVisible }) {
                    await model.refresh()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard (notification.object as? NSWindow)?.title == "Task Browser" else { return }
            Task { await model.refresh() }
        }
        .onChange(of: model.selection) { _, _ in model.cancelEditing() }
        .alert(deleteTitle, isPresented: $confirmsDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await model.deleteSelected() } }
        } message: {
            Text(deleteMessage)
        }
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
                TextField(
                    "Taskwarrior filter",
                    text: Binding(get: { model.rawFilter }, set: model.updateRawFilter)
                )
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Taskwarrior Filter")
                if !model.rawFilter.isEmpty {
                    Button {
                        model.updateRawFilter("")
                    } label: {
                        Label("Clear Filter", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)

            Divider()

            if let errorMessage = model.errorMessage, model.tasks.isEmpty {
                ContentUnavailableView(
                    "Couldn’t Load Tasks",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if !model.isLoading && model.tasks.isEmpty {
                ContentUnavailableView("No Tasks", systemImage: "checkmark.circle")
            } else {
                Table(
                    model.displayedTasks,
                    selection: $model.selection,
                    sortOrder: Binding(get: { model.tableSortOrder }, set: model.updateSortOrder)
                ) {
                    TableColumn("Description", value: \.description) { task in
                        HStack(spacing: 5) {
                            TaskStateIndicators(task: task)
                            Text(task.description)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 220, ideal: 360)

                    TableColumn("Project", value: \.project) { task in Text(task.project).lineLimit(1) }
                        .width(min: 80, ideal: 120)
                    TableColumn("Tags", value: \.tagsText) { task in Text(task.tagsText).lineLimit(1) }
                        .width(min: 80, ideal: 130)
                    TableColumn("Due", value: \.due) { task in Text(task.due).lineLimit(1) }
                        .width(min: 90, ideal: 120)
                    TableColumn("Priority", value: \.priority) { task in Text(task.priority).lineLimit(1) }
                        .width(65)
                    TableColumn("Urgency", value: \.urgency) { task in
                        Text(task.urgency.formatted(.number.precision(.fractionLength(1))))
                            .monospacedDigit()
                    }
                    .width(70)
                }
                .contextMenu(forSelectionType: UUID.self) { selection in
                    contextMenu(for: selection)
                } primaryAction: { selection in
                    guard selection.count == 1, !model.isEditing else { return }
                    model.selection = selection
                    DispatchQueue.main.async { model.beginEditing() }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
            }
        }
    }

    @ToolbarContentBuilder
    private var browserToolbar: some ToolbarContent {
        ToolbarItemGroup {
            if let errorMessage = model.errorMessage, !model.tasks.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(errorMessage)
            }

            if model.selectionCount > 0 {
                Button {
                    model.beginEditing()
                } label: {
                    toolbarLabel(model.selectionCount == 1 ? "Edit" : "Bulk Edit", systemImage: "pencil")
                }
                .disabled(model.isMutating || model.isEditing)
            }

            if model.selectionCanStart {
                Button {
                    Task { await model.startSelected() }
                } label: {
                    toolbarLabel("Start", systemImage: "play.fill")
                }
                .disabled(model.isMutating || model.isEditing)
            }

            if model.selectionCanStop {
                Button {
                    Task { await model.stopSelected() }
                } label: {
                    toolbarLabel("Stop", systemImage: "stop.fill")
                }
                .disabled(model.isMutating || model.isEditing)
            }

            if model.selectionCanComplete {
                Button {
                    Task { await model.completeSelected() }
                } label: {
                    toolbarLabel("Complete", systemImage: "checkmark.circle")
                }
                .disabled(model.isMutating || model.isEditing)
            }

            Menu {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    confirmsDelete = true
                }
                .disabled(model.selectionCount == 0 || model.isMutating || model.isEditing)
            } label: {
                toolbarLabel("More", systemImage: "ellipsis.circle")
            }

            Button {
                Task { await model.undo() }
            } label: {
                toolbarLabel("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo || model.isEditing)

            Button {
                Task { await model.refresh() }
            } label: {
                toolbarLabel("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
        }
    }

    private func toolbarLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private func contextMenu(for selection: Set<UUID>) -> some View {
        let records = model.tasks.filter { selection.contains($0.id) }
        if !records.isEmpty, !model.isEditing {
            Button(records.count == 1 ? "Edit" : "Bulk Edit", systemImage: "pencil") {
                model.selection = selection
                DispatchQueue.main.async { model.beginEditing() }
            }
        }
        if !model.isEditing, !records.isEmpty {
            if records.contains(where: {
                ($0.status == "pending" || $0.status == "waiting") && !$0.isActive
            }) {
                Button("Start", systemImage: "play.fill") {
                    model.selection = selection
                    Task { await model.startSelected() }
                }
            }
            if records.contains(where: {
                ($0.status == "pending" || $0.status == "waiting") && $0.isActive
            }) {
                Button("Stop", systemImage: "stop.fill") {
                    model.selection = selection
                    Task { await model.stopSelected() }
                }
            }
            if records.contains(where: { $0.status == "pending" || $0.status == "waiting" }) {
                Button("Complete", systemImage: "checkmark.circle") {
                    model.selection = selection
                    Task { await model.completeSelected() }
                }
            }
        }
        if !records.isEmpty, !model.isEditing {
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                model.selection = selection
                confirmsDelete = true
            }
        }
    }

    private var commandActions: TaskBrowserCommandActions {
        TaskBrowserCommandActions(
            canEdit: model.selectionCount > 0 && !model.isMutating && !model.isEditing,
            canStart: model.selectionCanStart && !model.isMutating && !model.isEditing,
            canStop: model.selectionCanStop && !model.isMutating && !model.isEditing,
            canComplete: model.selectionCanComplete && !model.isMutating && !model.isEditing,
            canDelete: model.selectionCount > 0 && !model.isMutating && !model.isEditing,
            canUndo: model.canUndo && !model.isEditing,
            editTitle: model.selectionCount > 1 ? "Bulk Edit Tasks" : "Edit Task",
            edit: model.beginEditing,
            start: { Task { await model.startSelected() } },
            stop: { Task { await model.stopSelected() } },
            complete: { Task { await model.completeSelected() } },
            delete: { confirmsDelete = true },
            undo: { Task { await model.undo() } },
            refresh: { Task { await model.refresh() } }
        )
    }

    private var deleteTitle: String {
        model.selectionCount == 1 ? "Delete task?" : "Delete \(model.selectionCount) tasks?"
    }

    private var deleteMessage: String {
        let subject = model.selectionCount == 1 ? "the selected task" : "the selected tasks"
        return "This marks \(subject) as deleted in Taskwarrior. "
            + "You can undo the operation until another Browser mutation replaces it."
    }
}

private struct BrowserSidebar: View {
    @ObservedObject var model: TaskBrowserViewModel

    var body: some View {
        List {
            Section("Views") {
                ForEach(BrowserViewKind.allCases, id: \.self) { view in
                    sidebarButton(view.title, icon: icon(for: view), selected: model.view == view) {
                        Task { await model.selectView(view) }
                    }
                }
            }

            if !model.projects.isEmpty {
                Section("Projects") {
                    sidebarButton("All Projects", icon: "tray", selected: model.project == nil) {
                        Task { await model.selectProject(nil) }
                    }
                    ForEach(model.projects, id: \.self) { project in
                        sidebarButton(project, icon: "folder", selected: model.project == project) {
                            Task { await model.selectProject(project) }
                        }
                    }
                }
            }

            if !model.tags.isEmpty {
                Section("Tags") {
                    sidebarButton("All Tags", icon: "tag", selected: model.tag == nil) {
                        Task { await model.selectTag(nil) }
                    }
                    ForEach(model.tags, id: \.self) { tag in
                        sidebarButton(tag, icon: "tag", selected: model.tag == tag) {
                            Task { await model.selectTag(tag) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarButton(
        _ title: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    private func icon(for view: BrowserViewKind) -> String {
        switch view {
        case .next: "list.bullet"
        case .waiting: "clock"
        case .completed: "checkmark.circle"
        }
    }
}

private struct TaskStateIndicators: View {
    let task: TaskRecord

    var body: some View {
        HStack(spacing: 2) {
            if task.isActive { Image(systemName: "play.fill").help("Active") }
            if task.isBlocked { Image(systemName: "lock.fill").help("Blocked") }
            if task.isRecurring { Image(systemName: "repeat").help("Recurring") }
            if task.isAnnotated { Image(systemName: "text.bubble").help("Annotated") }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private struct TaskInspector: View {
    @ObservedObject var model: TaskBrowserViewModel

    var body: some View {
        Group {
            if let task = model.selectedTask {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if model.edits != nil {
                            editor
                        } else {
                            Text(task.description)
                                .font(.title3.weight(.semibold))
                                .textSelection(.enabled)
                        }

                        Divider()

                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                            ForEach(task.sortedFields, id: \.key) { field in
                                GridRow {
                                    Text(field.key)
                                        .foregroundStyle(.secondary)
                                    if field.key == "annotations" {
                                        AnnotationList(value: field.value)
                                    } else {
                                        Text(displayValue(for: field.key, value: field.value))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        .font(.callout)
                    }
                    .padding(16)
                }
            } else if model.selectionCount > 1 {
                if model.bulkEdits != nil {
                    bulkEditor
                } else {
                    multiSelection
                }
            } else {
                ContentUnavailableView("No Selection", systemImage: "sidebar.right")
            }
        }
    }

    private var multiSelection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("\(model.selectionCount) Tasks Selected")
                .font(.headline)
            Text("Use the toolbar, Task menu, or secondary click to act on this selection.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Description") {
                TextField("Description", text: editBinding(\.description))
            }
            LabeledContent("Project") {
                AutocompleteTextField(
                    text: editBinding(\.project),
                    prompt: "Project",
                    suggestions: model.projects
                )
                .frame(minWidth: 160, minHeight: 22)
            }
            LabeledContent("Tags") {
                TagTokenField(tags: tagsBinding, suggestions: model.tags)
                    .frame(minWidth: 160, minHeight: 22)
            }
            LabeledContent("Due") {
                TextField("Due", text: editBinding(\.due))
            }
            LabeledContent("Priority") {
                PriorityPicker(
                    selection: editBinding(\.priority),
                    priorities: model.configuredPriorities
                )
                .frame(width: 120, height: 22)
            }
            HStack {
                Button("Cancel", action: model.cancelEditing)
                Button("Save") { Task { await model.saveEditing() } }
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(model.isMutating)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var bulkEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit \(model.selectionCount) Tasks")
                    .font(.headline)

                Toggle("Set Project", isOn: bulkProjectEnabled)

                if model.bulkEdits?.project != nil {
                    AutocompleteTextField(
                        text: bulkProjectBinding,
                        prompt: "Project",
                        suggestions: model.projects
                    )
                    .frame(minWidth: 180, minHeight: 22)
                    Text("Leave blank to clear the Project from every selected task.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Add Tags") {
                    TagTokenField(tags: bulkTagsToAddBinding, suggestions: model.tags)
                        .frame(minWidth: 180, minHeight: 22)
                }

                LabeledContent("Remove Tags") {
                    TagTokenField(tags: bulkTagsToRemoveBinding, suggestions: model.tags)
                        .frame(minWidth: 180, minHeight: 22)
                }

                HStack {
                    Button("Cancel", action: model.cancelEditing)
                    Button("Apply") { Task { await model.saveEditing() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.bulkEdits?.isEmpty != false)
                }
                .disabled(model.isMutating)
            }
            .padding(16)
        }
    }

    private func editBinding(_ keyPath: WritableKeyPath<TaskEdits, String>) -> Binding<String> {
        Binding(
            get: { model.edits?[keyPath: keyPath] ?? "" },
            set: { model.edits?[keyPath: keyPath] = $0 }
        )
    }

    private var tagsBinding: Binding<[String]> {
        Binding(
            get: { model.edits?.tags ?? [] },
            set: { model.edits?.tags = $0 }
        )
    }

    private var bulkProjectEnabled: Binding<Bool> {
        Binding(
            get: { model.bulkEdits?.project != nil },
            set: { enabled in model.bulkEdits?.project = enabled ? "" : nil }
        )
    }

    private var bulkProjectBinding: Binding<String> {
        Binding(
            get: { model.bulkEdits?.project ?? "" },
            set: { model.bulkEdits?.project = $0 }
        )
    }

    private var bulkTagsToAddBinding: Binding<[String]> {
        Binding(
            get: { model.bulkEdits?.tagsToAdd ?? [] },
            set: { tags in
                model.bulkEdits?.tagsToAdd = tags
                model.bulkEdits?.tagsToRemove.removeAll { tags.contains($0) }
            }
        )
    }

    private var bulkTagsToRemoveBinding: Binding<[String]> {
        Binding(
            get: { model.bulkEdits?.tagsToRemove ?? [] },
            set: { tags in
                model.bulkEdits?.tagsToRemove = tags
                model.bulkEdits?.tagsToAdd.removeAll { tags.contains($0) }
            }
        )
    }

    private func displayValue(for key: String, value: JSONValue) -> String {
        let dateFields = ["entry", "modified", "due", "wait", "scheduled", "until", "start", "end"]
        guard dateFields.contains(key), case let .string(rawDate) = value,
              let date = TaskwarriorDate.parse(rawDate) else {
            return value.displayValue
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct AnnotationList: View {
    let value: JSONValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(annotations, id: \.entry) { annotation in
                VStack(alignment: .leading, spacing: 1) {
                    Text(TaskwarriorDate.parse(annotation.entry)?.formatted(date: .abbreviated, time: .shortened)
                        ?? annotation.entry)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(annotation.description)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var annotations: [(entry: String, description: String)] {
        guard case let .array(values) = value else { return [] }
        return values.compactMap { value in
            guard case let .object(fields) = value,
                  case let .string(entry) = fields["entry"],
                  case let .string(description) = fields["description"] else { return nil }
            return (entry, description)
        }
        .sorted { $0.entry < $1.entry }
    }
}

private enum TaskwarriorDate {
    static func parse(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.date(from: value)
    }
}
