local deps = ...

local logging = deps.logging
local moduleHost = deps.moduleHost
local coordinator = deps.coordinator
local overlays = deps.overlays
local runtime = deps.runtime
local rom = deps.rom
local modutil = deps.modutil
local SetupRunData = deps.gameDeps.runData.SetupRunData

---@class StandaloneRuntime
---@field renderWindow fun()
---@field addMenuBar fun()
---@field handleHostGuiClosed fun()

local DEFAULT_WINDOW_WIDTH = 960
local DEFAULT_WINDOW_HEIGHT = 720

runtime.standalone = runtime.standalone or {}
-- Hot-reload-stable standalone runtime. Bridges and GUI callbacks late-read
-- this table so replacement module hosts can swap behavior without new handles.
runtime.standalone.runtimes = runtime.standalone.runtimes or {}
runtime.standalone.fallbackHud = runtime.standalone.fallbackHud or {}

local standaloneState = runtime.standalone
local runtimes = standaloneState.runtimes
local standalone = {}

local fallbackHud = import('core/standalone_host/private_fallback_hud.lua', nil, {
    moduleHost = moduleHost,
    coordinator = coordinator,
    overlays = overlays,
    runtimes = runtimes,
    state = standaloneState.fallbackHud,
})

local function validatePluginGuid(apiName, pluginGuid)
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        logging.violate("host.invalid_standalone_binding", "%s: pluginGuid is required", apiName)
    end
end

local function getStandaloneRuntime(pluginGuid)
    local activeRuntime = runtimes[pluginGuid]
    if type(activeRuntime) ~= "table" then
        return nil
    end
    return activeRuntime
end

local function disposeStandaloneRuntime(pluginGuid, activeRuntime)
    if type(activeRuntime) ~= "table" then
        return true, nil
    end

    local closeOk, closeErr = true, nil
    if type(activeRuntime.handleHostGuiClosed) == "function" then
        closeOk, closeErr = pcall(activeRuntime.handleHostGuiClosed)
    end

    if runtimes[pluginGuid] == activeRuntime then
        runtimes[pluginGuid] = nil
        fallbackHud.refreshMarker()
    end

    if not closeOk then
        return false, closeErr
    end
    return true, nil
end

local function warnStandaloneRuntimeDispose(pluginGuid, err)
    logging.violate(
        "host.retire_failed",
        "standalone runtime '%s' retirement failed: %s",
        tostring(pluginGuid),
        tostring(err)
    )
end

local function attachRuntimeReceipt(pluginGuid, host, activeRuntime)
    if not moduleHost.getState(host) then
        return
    end

    moduleHost.addEffectReceipt(host, "standalone", {
        dispose = function()
            return disposeStandaloneRuntime(pluginGuid, activeRuntime)
        end,
    })
end

--- Creates stable callbacks that late-read the current standalone runtime.
---@param pluginGuid string Plugin guid used when creating the module host.
---@return StandaloneRuntime bridge Standalone bridge with `renderWindow` and `addMenuBar` callbacks.
function standalone.standaloneUiBridge(pluginGuid)
    validatePluginGuid("standaloneUiBridge", pluginGuid)

    local function callRuntime(method)
        local activeRuntime = getStandaloneRuntime(pluginGuid)
        local callback = activeRuntime and activeRuntime[method] or nil
        if type(callback) == "function" then
            return callback()
        end
    end

    return {
        renderWindow = function()
            return callRuntime("renderWindow")
        end,
        addMenuBar = function()
            return callRuntime("addMenuBar")
        end,
        handleHostGuiClosed = function()
            return callRuntime("handleHostGuiClosed")
        end,
    }
end

local function isCoordinated(identity)
    return identity.modpack and coordinator.isRegistered(identity.modpack) or false
end

--- Initializes standalone module hosting and returns window/menu-bar renderers.
---@param pluginGuid string Plugin guid used when creating the module host.
---@return StandaloneRuntime runtime Standalone runtime with `renderWindow` and `addMenuBar` callbacks.
function standalone.standaloneHost(pluginGuid)
    validatePluginGuid("standaloneHost", pluginGuid)
    local host = moduleHost.getLiveHost(pluginGuid)
    if type(host) ~= "table" then
        logging.violate(
            "host.invalid_standalone_binding",
            "standaloneHost: no live module host is registered for current module '%s'",
            tostring(pluginGuid)
        )
    end

    local function getIdentity()
        return host.getIdentity() or {}
    end

    local function getMeta()
        return host.getMeta() or {}
    end

    local showWindow = false
    local didSeedWindowSize = false
    local runDataDirty = false
    local uiSuppressionToken = nil

    local function markRunDataDirty()
        if host.affectsRunData() then
            runDataDirty = true
        end
    end

    local function flushPendingRunData()
        if not runDataDirty then
            return
        end
        SetupRunData()
        runDataDirty = false
    end

    local function suppressOverlays()
        if not uiSuppressionToken then
            uiSuppressionToken = overlays.suppressForUi()
        end
    end

    local function releaseOverlaySuppression()
        if uiSuppressionToken then
            uiSuppressionToken.release()
            uiSuppressionToken = nil
        end
    end

    local function handleHostGuiClosed()
        flushPendingRunData()
        releaseOverlaySuppression()
    end

    local function setWindowOpen(open)
        open = open == true
        if showWindow == open then
            return
        end

        if open then
            showWindow = true
            suppressOverlays()
            return
        end

        flushPendingRunData()
        showWindow = false
        releaseOverlaySuppression()
    end

    local function seedWindowSize(imgui)
        if didSeedWindowSize then
            return
        end
        imgui.SetNextWindowSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, rom.ImGuiCond.FirstUseEver)
        didSeedWindowSize = true
    end

    local function renderWindow()
        local identity = getIdentity()
        local meta = getMeta()
        if isCoordinated(identity) then
            return
        end
        if not showWindow then
            return
        end

        suppressOverlays()

        local imgui = rom.ImGui
        local title = tostring(meta.name or identity.id or "Module") .. "###" .. tostring(identity.id)
        seedWindowSize(imgui)
        local open, shouldDraw = imgui.Begin(title, showWindow)
        if shouldDraw then
            local enabled = host.read("Enabled") == true
            local enabledValue, enabledChanged = imgui.Checkbox("Enabled", enabled)
            if enabledChanged then
                local ok, err = host.setEnabled(enabledValue)
                if ok then
                    markRunDataDirty()
                else
                    logging.violate("host.enable_transition_failed", "%s %s failed: %s",
                        tostring(meta.name or identity.id or "module"),
                        enabledValue and "enable" or "disable",
                        tostring(err))
                end
            end

            local debugValue, debugChanged = imgui.Checkbox("Debug Mode", host.read("DebugMode") == true)
            if debugChanged then
                host.setDebugMode(debugValue)
            end

            if imgui.Button("Resync Session") then
                host.resync()
            end

            imgui.Separator()
            imgui.Spacing()
            host.drawTab(imgui)
            local ok, err, committed = host.commitIfDirty()
            if ok and committed and host.read("Enabled") == true then
                markRunDataDirty()
            elseif ok == false then
                logging.violate(
                    "host.session_commit_failed",
                    "%s session commit failed; restored previous config where possible: %s",
                    tostring(meta.name or identity.id or "module"),
                    tostring(err)
                )
            end
        end
        imgui.End()
        if open == false then
            setWindowOpen(false)
        end
    end

    local function addMenuBar()
        local identity = getIdentity()
        local meta = getMeta()
        if isCoordinated(identity) then return end
        if rom.ImGui.BeginMenu(meta.name) then
            if rom.ImGui.MenuItem(meta.name) then
                setWindowOpen(not showWindow)
            end
            rom.ImGui.EndMenu()
        end
    end

    local activeRuntime = {
        renderWindow = renderWindow,
        addMenuBar = addMenuBar,
        handleHostGuiClosed = handleHostGuiClosed,
    }

    local previousRuntime = getStandaloneRuntime(pluginGuid)
    if previousRuntime and previousRuntime ~= activeRuntime then
        local disposeOk, disposeErr = disposeStandaloneRuntime(pluginGuid, previousRuntime)
        if not disposeOk then
            warnStandaloneRuntimeDispose(pluginGuid, disposeErr)
        end
    end

    runtimes[pluginGuid] = activeRuntime
    attachRuntimeReceipt(pluginGuid, host, activeRuntime)
    fallbackHud.refreshMarker()
    return activeRuntime
end

function standalone.handleHostGuiClosed()
    for _, activeRuntime in pairs(runtimes) do
        if type(activeRuntime.handleHostGuiClosed) == "function" then
            activeRuntime.handleHostGuiClosed()
        end
    end
end

function standalone.createFallbackMarker()
    return fallbackHud.createMarker()
end

local function installGuiCloseWatcher()
    if standaloneState.guiCloseWatcherRegistered then
        return
    end
    if not (rom and rom.gui and type(rom.gui.add_always_draw_imgui) == "function"
        and type(rom.gui.is_open) == "function") then
        return
    end

    standaloneState.guiCloseWatcherRegistered = true
    standaloneState.wasGuiOpen = rom.gui.is_open() == true
    rom.gui.add_always_draw_imgui(function()
        local isGuiOpen = rom.gui.is_open() == true
        if standaloneState.wasGuiOpen and not isGuiOpen
            and type(standaloneState.handleHostGuiClosed) == "function" then
            standaloneState.handleHostGuiClosed()
        end
        standaloneState.wasGuiOpen = isGuiOpen
    end)
end

standaloneState.handleHostGuiClosed = standalone.handleHostGuiClosed
public.standaloneUiBridge = standalone.standaloneUiBridge
public.standaloneHost = standalone.standaloneHost

installGuiCloseWatcher()

modutil.once_loaded.game(function()
    standalone.createFallbackMarker()
end)

return standalone
