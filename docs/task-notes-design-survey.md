# Task notes: Taskwarrior ecosystem design survey

Researched 2026-08-05 from the current [Taskwarrior tools catalog](https://taskwarrior.org/tools/) and the projects' own documentation, screenshots, and source. The catalog is generated from GitHub topics and currently contains hundreds of projects, so inclusion means “part of the ecosystem,” not Taskwarrior endorsement.

## Executive recommendation

Start with **sync-native annotations presented as a Notes section in the task inspector**:

- Show annotations as a compact chronological list, with timestamp, full text, and delete action.
- Put a multiline “Add note…” composer at the bottom and make adding a note fast from the keyboard.
- Keep the task description a one-line summary. Do not silently reinterpret it as a long-form notes field.
- Use plain text initially. Link detection is useful; Markdown rendering is not justified by Taskwarrior's data model.

This gives users the mental model they asked for—notes attached to a task—while staying completely compatible with Taskwarrior and its sync model. It also leaves a clean later extension point for an optional **single Markdown sidecar note**, if actual use shows that people need durable documents rather than timestamped updates.

The ecosystem does not show a compelling precedent for storing one rich, mutable long-form document directly inside Taskwarrior. The strongest long-form designs all add files and therefore add a second storage, backup, rename, deletion, and sync lifecycle.

## Native baseline

Taskwarrior explicitly defines an annotation as a text-string note attached to a task, allows any number of them, and notes that reports may display full annotations, a count, or only an indicator ([terminology](https://taskwarrior.org/docs/terminology/#annotation)). TaskChampion represents each one as a distinct timestamped key, `annotation_<timestamp>` ([task representation](https://taskwarrior.org/docs/task/#keys)). The task `description` is separately defined as the one-line summary. Annotation text is also included in Taskwarrior search ([searching](https://taskwarrior.org/docs/searching/)).

That data model naturally supports a chronological notes/log UI. It does **not** define Markdown, rich text, an editable monolithic body, attachments, or an explicit note title.

## Best comparators

### 1. taskwarrior-tui — list plus inspector and quick annotation

**Explicit behavior:** The selected task can expose a task-info view (`z`), its details scroll independently, and `A` opens `task <selected> annotate <string>` ([official keybindings](https://kdheepak.com/taskwarrior-tui/keybindings/)).

**Visible interaction pattern:** Tasks remain the primary list; secondary detail is revealed beside/below the list and annotations are added without navigating into a document editor.

**What TW Mac should borrow:** Keep Notes in the browser's task inspector, with selection preserved and an always-nearby add affordance. This is the best precedent for an annotations-first implementation.

### 2. taskwarrior-web-portal — annotations presented as Notes

**Explicit behavior:** The expanded task panel gives long fields including “Notes” a full-width row. Its edit modal includes an “Add a note…” input; the dedicated Add action appends while keeping the modal open, while Save can attach the note alongside structured edits. The implementation stores these notes with `task <id> annotate`, not in a separate notes field ([project README: row chrome](https://github.com/furan917/taskwarrior-web-portal#row-chrome), [project README: inline annotation on save](https://github.com/furan917/taskwarrior-web-portal#inline-annotation-on-save)).

**Visible interaction pattern:** Users see task-native annotations through familiar “Notes” language, with both a quick append path and a combined edit-and-note path. Storage semantics do not leak into the primary label.

**What TW Mac should borrow:** Call the inspector section **Notes**, describe each entry as a note, and keep timestamps visually secondary. Offer a lightweight composer directly in the inspector; structured task edits can remain a separate Save/Cancel flow.

### 3. taskn — one implicit Markdown sidecar per task

**Explicit behavior:** `taskn 1` opens a file named after the task UUID in `$EDITOR`; files are Markdown by default and live under `~/.taskn` unless configured otherwise. No marker annotation is required ([project README](https://github.com/crockeo/taskn#usage)).

**Visible interaction pattern:** Each task implicitly owns exactly one note. The user never manages filenames or a list of note objects; first edit can lazily create the file.

**What TW Mac could borrow later:** If annotations prove too fragmented for meeting notes, checklists, or research, add one “Open note” row per task and lazy-create a UUID-keyed Markdown file.

**Cost:** The note is not Taskwarrior data and will not follow Taskwarrior sync. TW Mac would own file backup, conflict handling, orphan cleanup, task deletion behavior, and discoverability outside the app.

### 4. Taskchamp — native task detail leading to an Obsidian-backed Markdown editor

**Explicit behavior:** Taskchamp's task edit form includes a bottom-bar “Create/Open Obsidian note” action and presents the note in a sheet. Its source implements a full-screen monospaced editor, rendered Markdown preview, automatic save on dismissal, and “Open in Obsidian” ([task form source](https://github.com/marriagav/taskchamp/blob/dev/taskchamp/Sources/View/EditTaskView.swift), [note editor source](https://github.com/marriagav/taskchamp/blob/dev/taskchamp/Sources/View/ObsidianNoteView.swift)). Configuration asks for an Obsidian vault and optional task folder ([official screenshot](https://raw.githubusercontent.com/marriagav/taskchamp/dev/fastlane/screenshots/en-US/2_APP_IPHONE_67_2.png.png)).

**Visible interaction pattern:** The task form stays structured and compact. Long-form writing is a separate focused surface, opened by one contextual action; edit and preview modes are distinct.

**What TW Mac should borrow if it adds Markdown:** Use a focused sheet/window rather than inserting a large editor into the compact inspector. Offer edit/preview, not a permanently rich text field.

**Cost:** This is explicitly an external-file integration. Its source includes settings/paywall/error branches and file/deep-link handling, illustrating how much product surface a “simple note” adds.

### 5. taskopen — annotations as links and attachments

**Explicit behavior:** taskopen recognizes file paths, URLs, and URIs stored in annotations and opens them. A special `Notes` or `Notes.<extension>` annotation can resolve to a UUID-keyed default note file. When several actionable annotations exist, taskopen presents a chooser; an optional inline command can preview the first lines of a file ([project README](https://github.com/jschlatow/taskopen#what-does-it-do)).

**Visible interaction pattern:** Annotations become a heterogeneous “linked resources” list rather than only prose: note, URL, PDF, image, spreadsheet, and command can each have an action.

**What TW Mac should borrow now:** Detect URLs in annotation text and make them clickable. A later linked-resources section could add file-type icons and Open/Edit actions without pretending the files are synced task data.

**Cost:** Paths are fragile across machines, and the Taskwarrior annotation is only a pointer or marker—not the content.

### 6. Taskwiki — the document is primary and tasks live inside it

**Explicit behavior:** Taskwiki synchronizes Vimwiki/Markdown-style checklist lines with Taskwarrior while ordinary surrounding prose and lists remain document content. Its task info split shows annotations inline under the task plus a modification history ([project README](https://github.com/tools-life/taskwiki#how-it-works)).

**Visible interaction pattern:** Notes provide the workspace and tasks are embedded in context, reversing TW Mac's current task-browser hierarchy.

**Assessment:** Interesting precedent for project planning, but it is a document/workspace product, not merely “notes on a task.” Following it now would greatly expand scope.

## Options for TW Mac

| Option | UX shape | Sync/portability | Complexity | Recommendation |
| --- | --- | --- | --- | --- |
| Annotation timeline | Inspector section with chronological entries and add composer | Native Taskwarrior data; searchable and syncable | Low | **Build first** |
| Single Markdown sidecar | “Open note” opens focused editor/preview | Local file unless separately synced | Medium–high | Validate after annotations ship |
| Linked resources | Annotation rows that open URLs/files | Pointer syncs; target often does not | Medium | Add URL detection now; defer files |
| Document workspace | Notes/documents contain tasks | Requires a new ownership and persistence model | Very high | Out of scope |

## Suggested first-pass interaction

1. Add a collapsible **Notes** section to the task inspector, below core task fields.
2. Render annotations oldest-to-newest, with timestamp in secondary text and selectable/wrapping body text.
3. Show an annotation-count badge in the task list only when nonzero.
4. Put a multiline composer at the bottom; `⌘Return` adds, `Esc` clears/dismisses, and empty input cannot be submitted.
5. Confirm deletion or provide immediate undo because Taskwarrior identifies annotations by timestamp/text rather than a user-facing stable ID.
6. Auto-link URLs. Preserve all other content as literal plain text.
7. Test real use before adding Markdown: the deciding evidence should be repeated need to revise one evolving body, not simply append timestamped context.

## Decision test after annotations ship

Add a dedicated Markdown note only if users repeatedly need one or more of these:

- revising a single evolving brief rather than appending updates;
- headings, checklists, code blocks, or substantial multi-paragraph content;
- content too long to scan as a chronology;
- export/open-in-editor workflows that justify a real file.

If those needs appear, the taskn storage rule (one UUID-keyed file) plus Taskchamp's focused edit/preview sheet is the strongest combined design precedent. Until then, annotations are the more coherent Taskwarrior-native answer.
