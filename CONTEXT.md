# Taskwarrior for Mac

A native Mac interface for working with tasks whose behavior and persistence remain owned by Taskwarrior.

## Language

**Taskwarrior**:
The authoritative task system, including task data, configuration, synchronization, hooks, recurrence, urgency, and user-defined attributes.
_Avoid_: Backend, storage layer, database

**Mac client**:
The native Mac interface through which a person views and changes Taskwarrior-owned tasks.
_Avoid_: Task manager, Taskwarrior replacement

**Quick Capture**:
A globally accessible, transient surface for creating a Taskwarrior task without switching away from the current workflow.
_Avoid_: Add dialog, main window

**Task Browser**:
The persistent surface for viewing and acting on Taskwarrior tasks, ordered by Urgency and filterable by Project and Tag.
_Avoid_: Dashboard, task database

**Description**:
The one-line text that identifies a task, corresponding to Taskwarrior's `description` attribute.
_Avoid_: Summary, title, notes

**Notes**:
The user-facing collection of supplementary text associated with a task. Each Note is stored as a Taskwarrior Annotation so it remains searchable and syncable. Editing replaces the old Annotation with a newly timestamped record containing the revised text.
_Avoid_: Description

**Annotation**:
A Taskwarrior-native timestamped text record that initially stores one Note. A task may have multiple Annotations, displayed as Notes in the Mac client.
_Avoid_: Description

**UDA**:
A user-defined Taskwarrior attribute whose value is preserved even when the Mac client does not understand its meaning.
_Avoid_: Client field, proprietary field

**Urgency**:
Taskwarrior's calculated score for how strongly a task demands attention, incorporating factors such as due date, blocking relationships, age, and Priority.
_Avoid_: Priority

**Priority**:
An explicit user-assigned Taskwarrior value such as `H`, `M`, or `L`, which may contribute to Urgency.
_Avoid_: Urgency

**Context**:
Taskwarrior's globally active workflow boundary, which filters visible tasks and may supply attributes to newly created tasks in both the CLI and Mac client.
_Avoid_: View, local filter, workspace
