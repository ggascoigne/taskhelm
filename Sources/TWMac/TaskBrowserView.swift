import AppKit
import SwiftUI
import TWMacCore
import UniformTypeIdentifiers

struct TaskBrowserRootView: View {
    @StateObject private var model: TaskBrowserViewModel
    @Environment(\.dismissWindow) private var dismissWindow

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
            .background(TaskBrowserWindowMarker())
            .onExitCommand {
                dismissWindow(id: "task-browser")
            }
    }
}

struct TaskBrowserView: View {
    @ObservedObject var model: TaskBrowserViewModel
    @State private var confirmsDelete = false
    @State private var resizeStart: CGFloat?
    @State private var boardDropTarget: BrowserBoardColumn?
    @State private var pendingPriorityDrop: PendingBoardPriorityDrop?

    private let dividerSize: CGFloat = 9
    private let minimumListWidth: CGFloat = 480
    private let minimumInspectorWidth: CGFloat = 260
    private let minimumListHeight: CGFloat = 260
    private let minimumInspectorHeight: CGFloat = 220

    var body: some View {
        NavigationSplitView {
            BrowserSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 280)
        } detail: {
            browserContent
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
            guard (notification.object as? NSWindow)?.identifier == .taskBrowserWindow else { return }
            Task { await model.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskwarriorTaskCreated)) { _ in
            Task { await model.refresh(reloadMetadata: true) }
        }
        .onChange(of: model.selection) { _, _ in model.cancelEditing() }
        .alert(deleteTitle, isPresented: $confirmsDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await model.deleteSelected() } }
        } message: {
            Text(deleteMessage)
        }
        .confirmationDialog(
            "Choose a priority",
            isPresented: Binding(
                get: { pendingPriorityDrop != nil },
                set: { if !$0 { pendingPriorityDrop = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let drop = pendingPriorityDrop {
                ForEach(boardPriorityChoices, id: \.self) { priority in
                    Button(boardPriorityTitle(priority)) {
                        pendingPriorityDrop = nil
                        Task {
                            await model.moveBoardTask(
                                drop.taskID,
                                into: drop.destination,
                                priority: priority
                            )
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingPriorityDrop = nil
            }
        } message: {
            Text("The task needs a priority to remain in To Do.")
        }
    }

    private var browserContent: some View {
        GeometryReader { geometry in
            switch model.detailsPosition {
            case .right:
                rightDetailsLayout(availableSize: geometry.size)
            case .bottom:
                bottomDetailsLayout(availableSize: geometry.size)
            }
        }
    }

    private func rightDetailsLayout(availableSize: CGSize) -> some View {
        let inspectorWidth = min(
            max(CGFloat(model.rightDetailsWidth), minimumInspectorWidth),
            max(minimumInspectorWidth, availableSize.width - minimumListWidth - dividerSize)
        )
        return HStack(spacing: 0) {
            taskList
                .frame(width: availableSize.width - inspectorWidth - dividerSize)
            BrowserResizeHandle(axis: .vertical) { translation in
                if resizeStart == nil { resizeStart = inspectorWidth }
                let requestedWidth = (resizeStart ?? inspectorWidth) - translation
                let maximumWidth = availableSize.width - minimumListWidth - dividerSize
                model.setRightDetailsWidth(Double(min(max(requestedWidth, minimumInspectorWidth), maximumWidth)))
            } onEnded: {
                resizeStart = nil
            }
            .frame(width: dividerSize)
            TaskInspector(model: model) {
                confirmsDelete = true
            }
                .frame(width: inspectorWidth)
        }
    }

    private func bottomDetailsLayout(availableSize: CGSize) -> some View {
        let inspectorHeight = min(
            max(CGFloat(model.bottomDetailsHeight), minimumInspectorHeight),
            max(minimumInspectorHeight, availableSize.height - minimumListHeight - dividerSize)
        )
        return VStack(spacing: 0) {
            taskList
                .frame(height: availableSize.height - inspectorHeight - dividerSize)
            BrowserResizeHandle(axis: .horizontal) { translation in
                if resizeStart == nil { resizeStart = inspectorHeight }
                let requestedHeight = (resizeStart ?? inspectorHeight) - translation
                let maximumHeight = availableSize.height - minimumListHeight - dividerSize
                model.setBottomDetailsHeight(Double(min(max(requestedHeight, minimumInspectorHeight), maximumHeight)))
            } onEnded: {
                resizeStart = nil
            }
            .frame(height: dividerSize)
            TaskInspector(model: model) {
                confirmsDelete = true
            }
                .frame(height: inspectorHeight)
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
                if model.view == .board {
                    taskBoard
                } else {
                    taskTable
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

    private var taskTable: some View {
        Table(
            model.displayedTasks,
            selection: $model.selection,
            sortOrder: Binding(get: { model.tableSortOrder }, set: model.updateSortOrder)
        ) {
            TableColumn("Description", value: \.description) { task in
                HStack(spacing: 5) {
                    ProjectColorBar(color: model.projectColor(for: task.project))
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
            TableColumn("Due", value: \.due) { task in
                Text(browserDueDisplayValue(task.due)).lineLimit(1)
            }
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

    private var taskBoard: some View {
        GeometryReader { geometry in
            let columnWidth = max(200, (geometry.size.width - 40) / 4)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(model.boardColumns) { column in
                        boardColumn(column)
                            .frame(width: columnWidth)
                    }
                }
                .padding(10)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
        }
        .accessibilityIdentifier("Task Board")
    }

    private func boardColumn(_ column: BrowserBoardColumnDefinition) -> some View {
        let tasks = model.tasks(in: column.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(column.title)
                    .font(.headline)
                Spacer()
                Text(tasks.count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        boardCard(task)
                    }
                }
            }
        }
        .padding(8)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .background(
            boardDropTarget == column.id ? Color.accentColor.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            if boardDropTarget == column.id {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .accessibilityIdentifier("Board Column \(column.title)")
        .onDrop(
            of: [.utf8PlainText],
            isTargeted: Binding(
                get: { boardDropTarget == column.id },
                set: { targeted in
                    if targeted {
                        boardDropTarget = column.id
                    } else if boardDropTarget == column.id {
                        boardDropTarget = nil
                    }
                }
            )
        ) { providers in
            loadBoardDrop(from: providers, into: column.id)
        }
    }

    private func boardCard(_ task: TaskRecord) -> some View {
        let isSelected = model.selection.contains(task.uuid)
        return BoardTaskCard(
            task: task,
            isSelected: isSelected,
            projectColor: model.projectColor(for: task.project)
        ) {
            model.selectBoardTask(task.uuid)
        }
        .contextMenu {
            contextMenu(for: [task.uuid])
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Board Card \(task.uuid.uuidString)")
        .onDrag {
            NSItemProvider(object: BoardDragPayload.string(for: task.uuid) as NSString)
        }
    }

    private func loadBoardDrop(
        from providers: [NSItemProvider],
        into destination: BrowserBoardColumn
    ) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let value = item as? NSString,
                  let taskID = BoardDragPayload.taskID(from: value as String) else { return }
            Task { @MainActor in
                _ = handleBoardDrop(taskID, into: destination)
            }
        }
        return true
    }

    private func handleBoardDrop(_ taskID: UUID, into destination: BrowserBoardColumn) -> Bool {
        guard model.canDropBoardTask(taskID, into: destination) else { return false }
        boardDropTarget = nil
        model.selectBoardTask(taskID)
        if model.boardDropNeedsPriority(taskID, into: destination) {
            pendingPriorityDrop = PendingBoardPriorityDrop(taskID: taskID, destination: destination)
        } else {
            Task { await model.moveBoardTask(taskID, into: destination) }
        }
        return true
    }

    private var boardPriorityChoices: [String] {
        let choices = model.configuredPriorities.filter { !$0.isEmpty }
        return choices.isEmpty ? ["H", "M", "L"] : choices
    }

    private func boardPriorityTitle(_ priority: String) -> String {
        switch priority {
        case "H": "High (H)"
        case "M": "Medium (M)"
        case "L": "Low (L)"
        default: priority
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

            Button {
                Task { await model.undo() }
            } label: {
                toolbarLabel("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo || model.isEditing)

            Button {
                model.setDetailsPosition(alternateDetailsPosition)
            } label: {
                toolbarLabel("Layout", systemImage: alternateDetailsPositionIcon)
            }
            .help("Move details pane to the \(alternateDetailsPosition.rawValue)")
            .accessibilityLabel("Move Details to \(alternateDetailsPosition.rawValue.capitalized)")

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

    private var alternateDetailsPosition: BrowserDetailsPosition {
        model.detailsPosition == .right ? .bottom : .right
    }

    private var alternateDetailsPositionIcon: String {
        switch alternateDetailsPosition {
        case .right: "sidebar.right"
        case .bottom: "rectangle.bottomhalf.inset.filled"
        }
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

private struct PendingBoardPriorityDrop {
    let taskID: UUID
    let destination: BrowserBoardColumn
}

enum BoardDragPayload {
    private static let prefix = "twmac-board-task:"

    static func string(for taskID: UUID) -> String {
        prefix + taskID.uuidString.lowercased()
    }

    static func taskID(from value: String) -> UUID? {
        guard value.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(value.dropFirst(prefix.count)))
    }
}

struct BoardTaskCard: View {
    let task: TaskRecord
    let isSelected: Bool
    var projectColor: ProjectColor? = nil
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    TaskStateIndicators(task: task)
                    Text(task.description)
                        .font(.callout.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }

                if !task.project.isEmpty {
                    Label(task.project, systemImage: "folder")
                        .lineLimit(1)
                }

                if !task.tags.isEmpty {
                    Label(task.tagsText, systemImage: "tag")
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if !task.due.isEmpty {
                        Label(browserDueDisplayValue(task.due), systemImage: "calendar")
                    }
                    if !task.priority.isEmpty {
                        Text(task.priority)
                            .font(.caption.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                            .help("Priority \(task.priority)")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                ProjectColorBar(color: projectColor)
                    .padding(.vertical, 6)
                    .padding(.leading, 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

private struct BrowserResizeHandle: View {
    let axis: Axis
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    var body: some View {
        ZStack {
            Color.clear
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(
                    width: axis == .vertical ? 1 : nil,
                    height: axis == .horizontal ? 1 : nil
                )
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    onChanged(axis == .vertical ? value.translation.width : value.translation.height)
                }
                .onEnded { _ in onEnded() }
        )
        .onHover { isHovering in
            guard isHovering else {
                NSCursor.arrow.set()
                return
            }
            (axis == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
        }
        .accessibilityLabel("Resize Details Pane")
    }
}

private struct BrowserSidebar: View {
    @ObservedObject var model: TaskBrowserViewModel
    @State private var showsCompletedProjects = false

    var body: some View {
        List {
            Section("Views") {
                ForEach(BrowserViewKind.allCases, id: \.self) { view in
                    sidebarButton(view.title, icon: icon(for: view), selected: model.view == view) {
                        Task { await model.selectView(view) }
                    }
                    .help(help(for: view))
                }
            }

            if !model.projects.isEmpty {
                Section("Projects") {
                    sidebarButton(
                        "All Projects",
                        icon: "tray",
                        selected: model.selectedProjects.isEmpty && model.selectedTags.isEmpty
                    ) {
                        Task { await model.clearFacetSelections() }
                    }
                    ForEach(model.activeProjects, id: \.self) { project in
                        projectRow(project)
                    }
                    if !model.completedProjects.isEmpty {
                        DisclosureGroup(isExpanded: $showsCompletedProjects) {
                            ForEach(model.completedProjects, id: \.self) { project in
                                projectRow(project)
                            }
                        } label: {
                            Text("Completed Projects (\(model.completedProjects.count))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !model.tags.isEmpty {
                Section("Tags") {
                    sidebarButton(
                        "All Tags",
                        icon: "tag",
                        selected: model.selectedProjects.isEmpty && model.selectedTags.isEmpty
                    ) {
                        Task { await model.clearFacetSelections() }
                    }
                    ForEach(model.tags, id: \.self) { tag in
                        sidebarButton(tag, icon: "tag", selected: model.selectedTags.contains(tag)) {
                            Task { await model.toggleTag(tag) }
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

    private func projectRow(_ project: String) -> some View {
        HStack(spacing: 7) {
            Button {
                Task { await model.toggleProject(project) }
            } label: {
                Label(project, systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ProjectColorWell(
                color: Binding(
                    get: { model.projectColor(for: project)?.color ?? .gray },
                    set: { model.setProjectColor(ProjectColor(color: $0), for: project) }
                ),
                label: "Color for \(project)"
            )
            .frame(width: 13, height: 13)
            .help("Choose color for \(project)")
        }
        .listRowBackground(
            model.selectedProjects.contains(project) ? Color.accentColor.opacity(0.18) : Color.clear
        )
    }

    private func icon(for view: BrowserViewKind) -> String {
        switch view {
        case .next: "list.bullet"
        case .waiting: "clock"
        case .completed: "checkmark.circle"
        case .board: "rectangle.split.3x1"
        }
    }

    private func help(for view: BrowserViewKind) -> String {
        switch view {
        case .next: "Tasks available to work on now, using your Taskwarrior next report filter."
        case .waiting: "Tasks deferred until their wait date; Taskwarrior normally hides them from Next until then."
        case .completed: "Completed tasks."
        case .board: "Kanban view combining tasks from Next with completed tasks."
        }
    }
}

private struct ProjectColorBar: View {
    let color: ProjectColor?

    var body: some View {
        Capsule()
            .fill(color?.color ?? Color.clear)
            .frame(width: 4)
            .frame(minHeight: 18)
            .accessibilityHidden(true)
    }
}

private struct TaskStateIndicators: View {
    let task: TaskRecord

    var body: some View {
        HStack(spacing: 2) {
            if task.isActive { Image(systemName: "play.fill").help("Active") }
            if task.isBlocked { Image(systemName: "lock.fill").help("Blocked") }
            if task.isRecurring { Image(systemName: "repeat").help("Recurring") }
            if task.isAnnotated {
                HStack(spacing: 1) {
                    Image(systemName: "text.bubble")
                    Text(task.annotationCount.formatted())
                        .monospacedDigit()
                }
                .help(task.annotationCount == 1 ? "1 note" : "\(task.annotationCount) notes")
                .accessibilityLabel(task.annotationCount == 1 ? "1 note" : "\(task.annotationCount) notes")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

private struct TaskInspector: View {
    @ObservedObject var model: TaskBrowserViewModel
    let confirmDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if model.selectionCount > 0 {
                actionBar
                Divider()
            }
            inspectorContent
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
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

                            TaskNotesSection(task: task, model: model)
                                .id(task.uuid)
                        }

                        Divider()

                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                            ForEach(task.sortedFields.filter { $0.key != "annotations" }, id: \.key) { field in
                                GridRow {
                                    Text(field.key)
                                        .foregroundStyle(.secondary)
                                    Text(displayValue(for: field.key, value: field.value))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                model.beginEditing()
            } label: {
                Label(model.selectionCount == 1 ? "Edit" : "Bulk Edit", systemImage: "pencil")
            }
            .disabled(model.isMutating || model.isEditing)

            if model.selectionCanStart {
                Button {
                    Task { await model.startSelected() }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(model.isMutating || model.isEditing)
            }

            if model.selectionCanStop {
                Button {
                    Task { await model.stopSelected() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(model.isMutating || model.isEditing)
            }

            if model.selectionCanComplete {
                Button {
                    Task { await model.completeSelected() }
                } label: {
                    Label("Complete", systemImage: "checkmark.circle")
                }
                .disabled(model.isMutating || model.isEditing)
            }

            Spacer(minLength: 0)

            Menu {
                Button("Delete", systemImage: "trash", role: .destructive, action: confirmDelete)
                    .disabled(model.isMutating || model.isEditing)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        .labelStyle(.titleAndIcon)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .frame(minHeight: 36)
        .background(.bar)
        .accessibilityIdentifier("Task Details Actions")
    }

    private var multiSelection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("\(model.selectionCount) Tasks Selected")
                .font(.headline)
            Text("Use the actions above, Task menu, or secondary click to act on this selection.")
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
                DueDateField(due: editBinding(\.due))
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
        if key == "due", case let .string(rawDate) = value {
            return browserDueDisplayValue(rawDate)
        }
        let dateFields = ["entry", "modified", "due", "wait", "scheduled", "until", "start", "end"]
        guard dateFields.contains(key), case let .string(rawDate) = value,
              let date = TaskwarriorDate.parse(rawDate) else {
            return value.displayValue
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct TaskNotesSection: View {
    let task: TaskRecord
    @ObservedObject var model: TaskBrowserViewModel
    @State private var isExpanded = true
    @State private var noteDraft = ""
    @State private var editingAnnotation: TaskAnnotation?
    @State private var annotationPendingDeletion: TaskAnnotation?
    @FocusState private var composerIsFocused: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if task.annotations.isEmpty {
                    Text("No notes yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(task.annotations) { annotation in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(formattedEntry(annotation))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Menu {
                                        Button("Edit Note", systemImage: "pencil") {
                                            beginEditing(annotation)
                                        }
                                        Button("Delete Note", systemImage: "trash", role: .destructive) {
                                            annotationPendingDeletion = annotation
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .frame(width: 18, height: 16)
                                    }
                                    .menuStyle(.borderlessButton)
                                    .fixedSize()
                                    .disabled(model.isMutating)
                                    .accessibilityLabel("Actions for note from \(formattedEntry(annotation))")
                                }
                                Text(linkified(annotation.description))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if annotation.id != task.annotations.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }

                noteComposer
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text("Notes")
                    .font(.headline)
                Spacer()
                if task.isAnnotated {
                    Text(task.annotationCount.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            "Delete note?",
            isPresented: deletionConfirmationIsPresented,
            presenting: annotationPendingDeletion
        ) { annotation in
            Button("Delete Note", role: .destructive) {
                deleteNote(annotation)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the note from Taskwarrior. You can undo the deletion until another Browser mutation replaces it.")
        }
    }

    private var noteComposer: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let editingAnnotation {
                HStack {
                    Label("Editing note from \(formattedEntry(editingAnnotation))", systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel Edit", action: cancelEditing)
                        .buttonStyle(.link)
                }
            }

            ZStack(alignment: .topLeading) {
                if noteDraft.isEmpty {
                    Text("Add a note…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 7)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $noteDraft)
                    .scrollContentBackground(.hidden)
                    .focused($composerIsFocused)
                    .padding(2)
                    .accessibilityLabel("New note")
            }
            .frame(minHeight: 72, maxHeight: 120)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.separator, lineWidth: 1)
            }
            .onKeyPress(keys: [.return]) { keyPress in
                guard keyPress.modifiers.contains(.command), canSubmit else { return .ignored }
                submitNote()
                return .handled
            }
            .onKeyPress(.escape) {
                cancelEditing()
                return .handled
            }

            HStack(spacing: 8) {
                Text("⌘↩ to add")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button(editingAnnotation == nil ? "Add Note" : "Save Note", action: submitNote)
                    .disabled(!canSubmit)
                    .accessibilityLabel(editingAnnotation == nil ? "Add Note" : "Save Note")
            }
        }
    }

    private var deletionConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { annotationPendingDeletion != nil },
            set: { isPresented in
                if !isPresented { annotationPendingDeletion = nil }
            }
        )
    }

    private var canSubmit: Bool {
        !noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isMutating
    }

    private func submitNote() {
        guard canSubmit else { return }
        let note = noteDraft
        let annotation = editingAnnotation
        Task {
            let succeeded: Bool
            if let annotation {
                succeeded = await model.replaceNote(annotation, with: note)
            } else {
                succeeded = await model.addNote(note)
            }
            if succeeded {
                noteDraft = ""
                editingAnnotation = nil
                composerIsFocused = true
            }
        }
    }

    private func beginEditing(_ annotation: TaskAnnotation) {
        editingAnnotation = annotation
        noteDraft = annotation.description
        isExpanded = true
        composerIsFocused = true
    }

    private func cancelEditing() {
        editingAnnotation = nil
        noteDraft = ""
        composerIsFocused = false
    }

    private func deleteNote(_ annotation: TaskAnnotation) {
        Task {
            if await model.deleteNote(annotation), editingAnnotation == annotation {
                cancelEditing()
            }
        }
    }

    private func formattedEntry(_ annotation: TaskAnnotation) -> String {
        TaskwarriorDate.parse(annotation.entry)?.formatted(date: .abbreviated, time: .shortened)
            ?? annotation.entry
    }

    private func linkified(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return result
        }
        let matches = detector.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
        for match in matches {
            guard let url = match.url,
                  let stringRange = Range(match.range, in: text),
                  let range = result.range(of: String(text[stringRange])) else { continue }
            result[range].link = url
        }
        return result
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

func browserDueDisplayValue(_ value: String) -> String {
    guard !value.isEmpty else { return "" }
    return TaskwarriorDate.parse(value)?.formatted(date: .abbreviated, time: .shortened) ?? value
}
