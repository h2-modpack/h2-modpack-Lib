local deps = ...

local moduleHost = deps.moduleHost
local coordinator = deps.coordinator
local overlays = deps.overlays
local runtimes = deps.runtimes
local state = deps.state

local FALLBACK_OWNER = "adamant-lib.fallback-hud"
local MARKER_TEXT = "Modded"

local fallbackHud = {}

local function isRuntimeUncoordinated(pluginGuid)
    local host = moduleHost.getLiveHost(pluginGuid)
    if type(host) ~= "table" or type(host.getIdentity) ~= "function" then
        return false
    end

    local identity = host.getIdentity() or {}
    return not (identity.modpack and coordinator.isRegistered(identity.modpack))
end

local function shouldShowFallbackMarker()
    for pluginGuid in pairs(runtimes) do
        if isRuntimeUncoordinated(pluginGuid) then
            return true
        end
    end
    return false
end

function fallbackHud.refreshMarker()
    overlays.dispatchCommit(FALLBACK_OWNER, {})
end

function fallbackHud.createMarker()
    if state.initialized then
        return
    end
    state.initialized = true
    overlays.defineSystem(FALLBACK_OWNER, function(registry)
        registry.createLine("marker", {
            componentName = "ModpackMark_StandaloneLib",
            region = "middleRightStack",
            order = 0,
            visible = shouldShowFallbackMarker,
            minWidth = 80,
        })
        registry.onCommit(function(ctx)
            ctx.setLine("marker", MARKER_TEXT)
            ctx.refresh("marker")
        end)
    end)
end

return fallbackHud
