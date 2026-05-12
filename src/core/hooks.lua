public.hooks = public.hooks or {}
public.hooks.Context = public.hooks.Context or {}
AdamantModpackLib_Internal.hooks = AdamantModpackLib_Internal.hooks or {}

local internal = AdamantModpackLib_Internal
local hooks = public.hooks
local internalHooks = internal.hooks
local REGISTRY_KEY = "__adamantHooks"
local ActiveOwnerStack = {}

local function getModUtil()
    local resolved = modutil
    if not resolved and rom and rom.mods then
        resolved = rom.mods["SGG_Modding-ModUtil"]
    end
    if not (resolved and resolved.mod and resolved.mod.Path) then
        internal.violate("hooks.modutil_unavailable", "lib.hooks: SGG_Modding-ModUtil is not available")
    end
    return resolved
end

local function getRegistry(owner)
    if type(owner) ~= "table" then
        internal.violate("hooks.invalid_registration", "lib.hooks: owner must be a persistent table")
    end

    local registry = owner[REGISTRY_KEY]
    if not registry then
        registry = {
            generation = 0,
            refreshing = false,
            slots = {},
        }
        owner[REGISTRY_KEY] = registry
    end
    return registry
end

local function parseRegistrationArgs(path, keyOrValue, maybeValue, valueName)
    if type(path) ~= "string" or path == "" then
        internal.violate("hooks.invalid_registration", "lib.hooks: path must be a non-empty string")
    end
    if maybeValue == nil then
        if keyOrValue == nil then
            internal.violate("hooks.invalid_registration", "lib.hooks: %s is required", valueName)
        end
        return path, keyOrValue
    end
    return tostring(keyOrValue), maybeValue
end

local function slotId(kind, path, key)
    return kind .. "\0" .. path .. "\0" .. key
end

local function getSlot(owner, kind, path, key)
    local registry = getRegistry(owner)
    local id = slotId(kind, path, key)
    local state = registry.slots[id]
    if not state then
        state = {
            kind = kind,
            path = path,
            key = key,
            registered = false,
        }
        registry.slots[id] = state
    end
    if registry.refreshing then
        state.generation = registry.generation
    end
    return state, registry
end

local function clearPendingState(state)
    state.pendingHandler = nil
    state.pendingReplacement = nil
    state.pendingContext = nil
end

local function applyWrapState(state)
    if state.pendingHandler ~= nil then
        state.handler = state.pendingHandler
    end

    if not state.registered then
        getModUtil().mod.Path.Wrap(state.path, function(base, ...)
            local current = state.handler
            if current then
                return current(base, ...)
            end
            return base(...)
        end)
        state.registered = true
    end
end

local function applyOverrideState(state)
    local replacement = state.pendingReplacement

    state.replacement = replacement

    if type(replacement) == "function" then
        if not state.registered then
            getModUtil().mod.Path.Override(state.path, function(...)
                local current = state.replacement
                if type(current) ~= "function" then
                    internal.violate("hooks.inactive_override", "lib.hooks.Override: function replacement is inactive")
                end
                return current(...)
            end)
            state.registered = true
            state.usesDispatcher = true
        elseif not state.usesDispatcher then
            local resolvedModUtil = getModUtil()
            resolvedModUtil.mod.Path.Restore(state.path)
            resolvedModUtil.mod.Path.Override(state.path, function(...)
                local current = state.replacement
                if type(current) ~= "function" then
                    internal.violate("hooks.inactive_override", "lib.hooks.Override: function replacement is inactive")
                end
                return current(...)
            end)
            state.usesDispatcher = true
        end
        return
    end

    if state.registered then
        getModUtil().mod.Path.Restore(state.path)
    end
    getModUtil().mod.Path.Override(state.path, replacement)
    state.registered = true
    state.usesDispatcher = false
end

local function applyContextWrapState(state)
    if state.pendingContext ~= nil then
        state.context = state.pendingContext
    end

    if not state.registered then
        getModUtil().mod.Path.Context.Wrap(state.path, function(...)
            local current = state.context
            if current then
                return current(...)
            end
        end)
        state.registered = true
    end
end

local function deactivateSlot(state)
    if state.kind == "wrap" then
        state.handler = nil
        return
    end

    if state.kind == "contextWrap" then
        state.context = nil
        return
    end

    if state.kind == "override" then
        state.replacement = nil
        if state.registered then
            getModUtil().mod.Path.Restore(state.path)
            state.registered = false
        end
    end
end

local function getActiveOwner(apiName)
    local owner = ActiveOwnerStack[#ActiveOwnerStack]
    if not owner then
        internal.violate(
            "hooks.no_active_owner",
            "lib.hooks.%s requires an active registerHooks context; use %sOwned(owner, ...) outside module activation",
            apiName,
            apiName
        )
    end
    return owner
end

--- Registers or updates a stable ModUtil Path.Wrap dispatcher using the active module owner.
---@param path string ModUtil path to wrap.
---@param keyOrHandler string|function Explicit hook key, or handler when no key is needed.
---@param maybeHandler function|nil Handler when an explicit key is supplied.
function hooks.Wrap(path, keyOrHandler, maybeHandler)
    return hooks.WrapOwned(getActiveOwner("Wrap"), path, keyOrHandler, maybeHandler)
end

--- Registers or updates a stable ModUtil Path.Wrap dispatcher for an explicit owner.
--- Re-running with the same owner/path/key updates the wrapped handler without stacking another wrapper.
---@param owner table Persistent module/framework internal table.
---@param path string ModUtil path to wrap.
---@param keyOrHandler string|function Explicit hook key, or handler when no key is needed.
---@param maybeHandler function|nil Handler when an explicit key is supplied.
function hooks.WrapOwned(owner, path, keyOrHandler, maybeHandler)
    local key, handler = parseRegistrationArgs(path, keyOrHandler, maybeHandler, "handler")
    if type(handler) ~= "function" then
        internal.violate("hooks.invalid_registration", "lib.hooks.Wrap: handler must be a function")
    end

    local state, registry = getSlot(owner, "wrap", path, key)
    if registry.refreshing then
        state.pendingHandler = handler
        return
    end

    state.pendingHandler = handler
    applyWrapState(state)
    clearPendingState(state)
end

--- Registers or updates a stable ModUtil Path.Override using the active module owner.
---@param path string ModUtil path to override.
---@param keyOrReplacement string|any Explicit hook key, or replacement when no key is needed.
---@param maybeReplacement any|nil Replacement when an explicit key is supplied.
function hooks.Override(path, keyOrReplacement, maybeReplacement)
    return hooks.OverrideOwned(getActiveOwner("Override"), path, keyOrReplacement, maybeReplacement)
end

--- Registers or updates a stable ModUtil Path.Override for an explicit owner.
--- Function replacements use a dispatcher so hot reloads update behavior without re-overriding.
---@param owner table Persistent module/framework internal table.
---@param path string ModUtil path to override.
---@param keyOrReplacement string|any Explicit hook key, or replacement when no key is needed.
---@param maybeReplacement any|nil Replacement when an explicit key is supplied.
function hooks.OverrideOwned(owner, path, keyOrReplacement, maybeReplacement)
    local key, replacement = parseRegistrationArgs(path, keyOrReplacement, maybeReplacement, "replacement")
    local state, registry = getSlot(owner, "override", path, key)
    if registry.refreshing then
        state.pendingReplacement = replacement
        return
    end

    state.pendingReplacement = replacement
    applyOverrideState(state)
    clearPendingState(state)
end

--- Registers or updates a stable ModUtil Path.Context.Wrap dispatcher using the active module owner.
---@param path string ModUtil path to context-wrap.
---@param keyOrContext string|function Explicit hook key, or context function when no key is needed.
---@param maybeContext function|nil Context function when an explicit key is supplied.
function hooks.Context.Wrap(path, keyOrContext, maybeContext)
    return hooks.Context.WrapOwned(getActiveOwner("Context.Wrap"), path, keyOrContext, maybeContext)
end

--- Registers or updates a stable ModUtil Path.Context.Wrap dispatcher for an explicit owner.
--- Removed context wraps become inert during host hook refresh; ModUtil has no safe path-level restore for one context wrapper.
---@param owner table Persistent module/framework internal table.
---@param path string ModUtil path to context-wrap.
---@param keyOrContext string|function Explicit hook key, or context function when no key is needed.
---@param maybeContext function|nil Context function when an explicit key is supplied.
function hooks.Context.WrapOwned(owner, path, keyOrContext, maybeContext)
    local key, context = parseRegistrationArgs(path, keyOrContext, maybeContext, "context")
    if type(context) ~= "function" then
        internal.violate("hooks.invalid_registration", "lib.hooks.Context.Wrap: context must be a function")
    end

    local state, registry = getSlot(owner, "contextWrap", path, key)
    if registry.refreshing then
        state.pendingContext = context
        return
    end

    state.pendingContext = context
    applyContextWrapState(state)
    clearPendingState(state)
end

--- Runs hook registration as one reload generation and deactivates registrations omitted by the callback.
---@param owner table Persistent module/framework internal table.
---@param register fun()
function internalHooks.refresh(owner, register)
    if type(register) ~= "function" then
        internal.violate("hooks.invalid_registration", "internal.hooks.refresh: register must be a function")
    end

    local registry = getRegistry(owner)
    registry.generation = registry.generation + 1
    registry.refreshing = true

    ActiveOwnerStack[#ActiveOwnerStack + 1] = owner
    local ok, err = pcall(register)
    ActiveOwnerStack[#ActiveOwnerStack] = nil
    registry.refreshing = false

    if ok then
        for id, state in pairs(registry.slots) do
            if state.generation ~= registry.generation then
                deactivateSlot(state)
                registry.slots[id] = nil
            elseif state.kind == "wrap" then
                applyWrapState(state)
                clearPendingState(state)
            elseif state.kind == "override" then
                applyOverrideState(state)
                clearPendingState(state)
            elseif state.kind == "contextWrap" then
                applyContextWrapState(state)
                clearPendingState(state)
            end
        end
    else
        for id, state in pairs(registry.slots) do
            if state.generation == registry.generation then
                clearPendingState(state)
                if not state.registered then
                    registry.slots[id] = nil
                end
            end
        end
    end

    if not ok then
        error(err, 0)
    end
end
