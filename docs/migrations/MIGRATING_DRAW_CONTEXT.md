# Migrating Draw Callbacks To Draw Context

This note covers the planned draw-callback API change from three live draw
arguments to one render-scoped context object.

## What Changed

Old draw callbacks receive separate live surfaces:

```lua
function ui.drawTab(imgui, session, host)
end

function ui.drawQuickContent(imgui, session, host)
end
```

New draw callbacks receive one render-scoped context:

```lua
function ui.drawTab(ctx)
end

function ui.drawQuickContent(ctx)
end
```

Module creation stays grep-visible and does not use a construction-time draw
factory:

```lua
local host = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = definition,
    drawTab = ui.drawTab,
    drawQuickContent = ui.drawQuickContent,
})
```

## Draw Context Shape

Lib creates the context at the host draw boundary for each render call.

```lua
---@class AdamantModpackLib.DrawContext
---@field imgui table
---@field session AdamantModpackLib.AuthorSession
---@field host AdamantModpackLib.AuthorHost
---@field widgets AdamantModpackLib.BoundWidgets
```

`ctx.widgets` is the bound widget surface. Widget calls no longer repeat
`imgui` and `session`:

```lua
function ui.drawTab(ctx)
    ctx.widgets.dropdown("Mode", {
        label = "Mode",
        values = { "Default", "Custom" },
    })

    ctx.widgets.checkbox("FeatureEnabled", {
        label = "Enable Feature",
    })

    ctx.imgui.SameLine()
end
```

## Why

The old callback shape kept module entrypoints simple, but it pushed the same
three live draw dependencies through every helper and subfile:

```lua
lib.widgets.checkbox(imgui, session, "FeatureEnabled", opts)
subPanel.draw(imgui, session, host)
```

The context shape keeps the entrypoint explicit while reducing module-side
plumbing:

```lua
subPanel.draw(ctx)
ctx.widgets.checkbox("FeatureEnabled", opts)
```

This intentionally differs from a `createDraw(...)` factory. `imgui`,
`session`, and `host` are live render/session surfaces, not static module
dependencies. They should enter the module at draw time, not be captured during
module construction.

## Related CreateModule Boundary Cleanup

This migration is expected to pair with flattening the author-facing
`lib.createModule(...)` options. The old nested `definition = { ... }` shape is
a remnant of the former explicit `prepareDefinition(...) -> createStore(...) ->
createHost(...)` construction path. If `createModule(...)` is the canonical
module-author API, it should accept definition fields directly and build the
pure prepared-definition input internally.

Target author shape:

```lua
local host = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,

    modpack = PACK_ID,
    id = MODULE_ID,
    name = "Example Module",
    shortName = "Example",
    tooltip = "...",
    storage = storage,
    hashGroupPlan = hashGroupPlan,

    drawTab = ui.drawTab,
    drawQuickContent = ui.drawQuickContent,
})
```

`hasQuickContent` should stay internal. Module authors should not provide it as
public config. `createModule(...)` should derive it from the callback surface
and pass it to `prepareDefinition(...)` as structural metadata:

```lua
local preparedDefinition = moduleHost.prepareDefinition(
    GetStructuralBaseline(opts.pluginGuid),
    definitionInput,
    {
        hasQuickContent = type(opts.drawQuickContent) == "function",
    }
)
```

That keeps the fingerprint behavior unchanged while making the structure
cleaner:

- `createModule(...)` owns public option shape and derives construction inputs.
- `prepareDefinition(...)` owns validation, fingerprinting, and prepared
  definition metadata.
- `drawQuickContent` remains an optional draw callback.
- `hasQuickContent` remains internal structural surface data, not author-owned
  module data.

## Migration Steps

1. Change draw callback signatures.

Before:

```lua
function ui.drawTab(imgui, session, host)
    lib.widgets.checkbox(imgui, session, "FeatureEnabled", {
        label = "Enable Feature",
    })
end
```

After:

```lua
function ui.drawTab(ctx)
    ctx.widgets.checkbox("FeatureEnabled", {
        label = "Enable Feature",
    })
end
```

2. Pass one context object to inner UI files.

Before:

```lua
components.draw(imgui, session, host)
```

After:

```lua
components.draw(ctx)
```

3. Keep static module dependencies in normal module binding.

```lua
local ui = {}
local catalog
local components

function ui.bind(deps)
    catalog = deps.catalog
    components = import("mods/ui/components.lua").bind({
        catalog = catalog,
    })
    return ui
end
```

`ctx` is for render-scoped live surfaces only. Do not store it across frames,
hot reloads, or module activation boundaries.

## Rules

- Keep `drawTab = ui.drawTab` and `drawQuickContent = ui.drawQuickContent` in
  module creation.
- Do not introduce `createDraw(...)` for normal module authoring.
- Use `ctx.widgets.*` for Lib widgets that bind to `imgui` and `session`.
- Use `ctx.imgui` for raw ImGui layout calls.
- Use `ctx.session` only when direct staged-state access is clearer than a
  widget helper.
- Use `ctx.host` for host capabilities such as metadata, logging, enabled
  checks, or reset helpers.
- Keep static module data, catalogs, and action services in `ui.bind(...)`.
