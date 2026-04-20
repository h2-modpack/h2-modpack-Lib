# Changelog

## [Unreleased] - UI Lean-Down

Complete removal of the v2 declarative UI tree and registry model. This release is not backward-compatible with modules targeting v2 declarative authoring.

### Breaking Changes

**Declarative UI tree removed**

The entire `definition.ui` / `definition.customTypes` authoring model is gone.

Removed:
- `lib.ui.*` namespace
- `lib.registry.*` namespace
- `lib.accessors.*` namespace
- `lib.definition.*` namespace
- `src/compat/legacy_api.lua`
- `field_registry/` source directory
- `lib.registry.widgetHelpers.drawStructuredAt(...)` and `estimateRowAdvanceY(...)`

`definition.ui`, `definition.customTypes`, and `selectQuickUi` are now ignored. Lib warns in debug mode if they are present.

`category`, `subgroup`, and `placement` on module definitions are ignored.

**Widget and layout draw contracts removed**

The rect-based draw contract `(imgui, node, bound, x, y, availWidth, availHeight, uiState)` -> `(consumedWidth, consumedHeight, changed)` is gone.

Layout types removed: `vstack`, `hstack`, `tabs`, `collapsible`, `scrollRegion`, `split`.

Custom widget/layout registry extension is no longer supported.

**`lib.special.*` replaced by top-level host/lifecycle helpers**

`lib.special.runPass` and `lib.special.getCachedPreparedNode` are removed with no replacement.

Remaining helpers migrated:
- `lib.special.auditAndResyncState` -> `lib.lifecycle.resyncSession`
- `lib.special.commitState` -> `lib.lifecycle.commitSession`
- `lib.special.standaloneUI` -> `lib.standaloneHost`

**`lib.ui.*` nav helpers replaced by `lib.nav.*`**

- `lib.ui.verticalTabs` -> `lib.nav.verticalTabs`
- `lib.ui.isVisible` -> `lib.nav.isVisible`

**Managed store/session split**

`lib.createStore(config, definition, dataDefaults?)` now returns two values:
- `store` for persisted runtime reads
- `session` for staged UI state

Removed from managed store instances:
- `store.uiState`
- `store.write`
- `store._write`
- `store.readBits`
- `store.writeBits`
- `store._readBits`
- `store._writeBits`
- `store.getPackedAliases`
- `store._getPackedAliases`
- `store.storage`

Persisted writes now go through:
- `lib.lifecycle.setEnabled(def, store, enabled)` for module enabled toggles
- `lib.lifecycle.setDebugMode(store, enabled)` for module debug toggles
- `session.write(alias, value)` plus `session.flushToConfig()` for profile/hash storage imports

Draw code should stage edits through:
- `session.write(alias, value)`

`session.view` remains public and read-only for immediate-mode draw readability.

Removed session compatibility methods:
- `session.get`
- `session.set`
- `session.toggle`
- `session.update`
- `session.getAliasNode`
- `session.reloadFromConfig`
- `session.collectConfigMismatches`

Current session surface:
- `session.view`
- `session.read(alias)`
- `session.write(alias, value)`
- `session.reset(alias)`
- `session.isDirty()`
- `session.flushToConfig()`
- `session.auditMismatches()`

**Widget feature removals**

- `confirmButton` timeout (`timeoutSeconds`) removed
- Stepper fast-step buttons (`<<` / `>>`) removed
- Stepper `valueColors` on the value slot removed

### Added

**`lib.widgets.*` - immediate-mode widget helpers**

Widgets are now direct draw functions, not registered node types. No preparation, no registry lookup, no draw contract.

New and retained widgets under `lib.widgets`:
- `separator`
- `text`
- `button`
- `confirmButton`
- `inputText`
- `dropdown`
- `mappedDropdown`
- `packedDropdown`
- `radio`
- `mappedRadio`
- `packedRadio`
- `stepper`
- `steppedRange`
- `checkbox`
- `packedCheckboxList`

**`lib.nav.*` - navigation helpers**

- `lib.nav.verticalTabs(imgui, opts)` - immediate-mode vertical tab rail
- `lib.nav.isVisible(session, condition)` - evaluates `visibleIf`-style conditions through `session.read(...)`

**`lib.lifecycle.*` - module lifecycle helpers**

- `lib.lifecycle.registerCoordinator(packId, config)` - registers coordinator config for a pack
- `lib.lifecycle.mutatesRunData(def)` - returns whether a definition opts into live run-data mutations
- `lib.lifecycle.applyMutation(def, store)`
- `lib.lifecycle.revertMutation(def, store)`
- `lib.lifecycle.reapplyMutation(def, store)`
- `lib.lifecycle.applyOnLoad(def, store)` - syncs startup live mutation state to effective enabled state
- `lib.lifecycle.resyncSession(def, store, session)`
- `lib.lifecycle.commitSession(def, store, session)`
- `lib.lifecycle.setEnabled(def, store, enabled)` - semantic helper for module enabled toggles and mutation lifecycle transitions
- `lib.lifecycle.setDebugMode(store, enabled)` - semantic helper for module debug toggles

**Top-level standalone host helper**

- `lib.standaloneHost(def, store, session, opts?)`

**`lib.hashing` additions**

- `lib.hashing.getPackWidth(node)` - public packed-width helper for hash grouping
- `lib.hashing.toHash(node, value)` / `lib.hashing.fromHash(node, str)` - public hash/profile value encoding
- `lib.hashing.readPackedBits(packed, offset, width)` - public raw packed-bit read helper
- `lib.hashing.writePackedBits(packed, offset, width, value)` - public raw packed-bit write helper

---
## [v2] — Layout Substrate Rewrite

Complete rewrite of the UI rendering substrate and registry model. This release is not backward-compatible with modules targeting v1.

### Breaking Changes

**Registry model**

- Single `FieldTypes` registry replaced by three separate registries: `lib.registry.storage`, `lib.registry.widgets`, `lib.registry.layouts`
- `definition.options` and `definition.stateSchema` are no longer supported; use `definition.storage` and `definition.ui`

**Layout types**

Old v1 layout types are removed: `separator`, `group`, `horizontalTabs`, `verticalTabs`, `panel`

Replacements:
- `group` → `vstack` (plain vertical grouping) or `collapsible` (collapsible section)
- `horizontalTabs` / `verticalTabs` → `tabs` with `orientation = "horizontal"` / `"vertical"`
- `panel` → `hstack` / `vstack` composition
- `separator` → `separator` widget (no longer a layout node)

**Widget draw contract**

Old: `draw(imgui, node, bound, width, uiState)`

New: `draw(imgui, node, bound, x, y, availWidth, availHeight, uiState)`

Widgets must return `consumedWidth, consumedHeight, changed`.

**Layout render contract**

Old: `render(imgui, node, drawChild)` returning `open` or `open, changed`

New: `render(imgui, node, drawChild, x, y, availWidth, availHeight, uiState, bound)` returning `consumedWidth, consumedHeight, changed`

**Geometry blocks removed**

`geometry = { slots = { ... } }` is no longer part of the widget contract. Replaced by direct node properties:
- `stepper` / `steppedRange` value slot: `valueWidth`, `valueAlign`
- `inputText` / `dropdown` / `mappedDropdown` control width: `controlWidth`
- `text` block width: `width`

`slots`, `dynamicSlots`, and `defaultGeometry` are removed from the custom widget type contract.

**API surface**

Flat `lib.*` names are replaced by a namespaced surface. Old names still work through `src/compat/legacy_api.lua` for existing modules but should not be used in new code.

### Added

**Storage types**

- `bool` — normalizes to `true`/`false`, hashes as `"1"`/`"0"`, packs as 1 bit
- `int` — normalizes with min/max clamp and floor, hashes as decimal string, packs with derivable width
- `string` — normalizes to string, optional `maxLen`
- `packedInt` — root type for alias-addressable packed bit partitions; child aliases are materialized automatically

**Widget types**

- `separator` — horizontal separator line; no binds
- `stepper` — `[−] value [+]` with optional `fastStep`; supports `displayValues`, `valueColors`
- `steppedRange` — paired min/max steppers sharing a label
- `button` — push button with optional `onClick` callback
- `confirmButton` — two-step confirmation button with configurable timeout
- `inputText` — text input bound to string storage; supports `controlWidth`
- `mappedDropdown` — dropdown with caller-supplied preview and option callbacks
- `packedDropdown` — dropdown over packed bit child aliases
- `mappedRadio` — radio group with caller-supplied option callbacks
- `packedRadio` — radio group over packed bit child aliases
- `packedCheckboxList` — checkbox list over packed child aliases; supports `filterText` and `filterMode` binds, `valueColors`

**Layout types**

- `vstack` — vertical child stack with configurable `gap`
- `hstack` — horizontal child stack with configurable `gap`
- `tabs` — horizontal or vertical tab container; supports `binds.activeTab` for alias-backed selection
- `collapsible` — collapsible section with `label` and `defaultOpen`
- `scrollRegion` — child-window-backed scrollable container
- `split` — two-pane split layout with `ratio`, `firstSize`, `secondSize`, and optional `gap`

**Managed UI state**

- `session` — transactional staging layer over persisted config, returned separately from `lib.createStore(...)`
- `session.view` — read-only proxy for safe draw-path reads
- `session.read` / `session.write` / `session.reset`
- `session.flushToConfig` — flush staged changes to persisted config
- `session.isDirty` — check whether any staged value has diverged from config
- Mismatch detection and snapshot/restore for transactional rollback

**Transient storage roots**

Storage nodes may declare `lifetime = "transient"` instead of `configKey`. Transient roots participate in `session` staging but do not persist, hash, or flush.

**Mutation lifecycle**

- `lib.mutation.createPlan()` — reversible mutation plan with `set`, `setMany`, `transform`, `append`, `appendUnique`, `removeElement`, `setElement`, `apply`, `revert`
- `lib.mutation.createBackup()` — isolated backup/restore pair
- `lib.lifecycle.inferMutation(def)` — infers lifecycle shape: `patch`, `manual`, `hybrid`
- `lib.lifecycle.applyMutation` / `lib.lifecycle.revertMutation` / `lib.lifecycle.reapplyMutation`
- Modules may declare `affectsRunData = true` to opt into run-data mutation behavior

**Namespaced API surface**

- `lib.definition.*`
- `lib.mutation.*`
- `lib.ui.*`
- `lib.resetStorageToDefaults(...)`
- `lib.hashing.*`
- `lib.special.*`
- `lib.logging.*`
- `lib.accessors.*`
- `lib.registry.*`

**Special module helpers**

- `lib.special.runPass(opts)` — orchestrated UI pass with commit/flush/callback flow
- `lib.special.getCachedPreparedNode(...)` — caller-owned prepared-node cache with rebuild detection
- `lib.special.auditAndResyncState(name, uiState)` — replaced by `lib.lifecycle.resyncSession(def, store, session)`
- `lib.special.commitState(def, store, uiState)` — replaced by `lib.lifecycle.commitSession(def, store, session)`
- `lib.special.standaloneUI(def, store, uiState?, opts?)` — replaced by `lib.standaloneHost(def, store, session, opts?)`

**Other**

- `visibleIf` on widget nodes — bool alias shorthand, `{ alias, value }`, or `{ alias, anyOf = { ... } }`
- `valueColors` on `checkbox`, `dropdown`, `radio`, `stepper`, `packedCheckboxList`
- `filterMode` bind on `packedCheckboxList` — `"all"`, `"checked"`, `"unchecked"`
- Printf-style logging — string formatting deferred past the enabled gate; no allocation when disabled
- `lib.registry.widgetHelpers.drawStructuredAt(...)` and `estimateRowAdvanceY(...)` as public helpers for custom widget authors

---

## [v1] — Initial Release

### Added

- `createStore(config, definition?)` — module store facade
- `standalone()` — menu-bar toggle callback for modules without coordinator hosting
- `isEnabled()` — checks module store and coordinator master toggle
- `readPath()` / `writePath()` — string and table-path accessors for nested config keys
- `drawField()` — ImGui widget renderer delegating to the FieldTypes registry
- `validateSchema()` — declaration-time field descriptor validation and metadata caching
- `createBackupSystem()` — isolated backup/revert with first-call-only semantics
- FieldTypes registry with `checkbox`, `dropdown`, and `radio` built-in types
- Unit tests (LuaUnit, Lua 5.1) for field types, path helpers, validation, backup, special state, and `isEnabled`
- CI with Luacheck linting and branch protection on `main`







