# Use operation-scoped undo

Browser mutations will support one level of client-scoped Undo by comparing full Taskwarrior state before and after an operation, then restoring that operation's complete footprint. This is preferred over `task undo`, whose global "most recent action" semantics could reverse an intervening CLI change; restoration must refuse rather than overwrite records changed by sync or another client after the operation.
