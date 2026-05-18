local lu = require("luaunit")
local createStandaloneHarness = require("tests/harness/create_standalone_harness")

TestStandaloneHost = {}

local PLUGIN_GUID = "test-standalone-module"

local function makeHost(opts)
    opts = opts or {}
    local calls = {
        setEnabled = {},
        setDebugMode = {},
        resync = 0,
        drawTab = 0,
        commitIfDirty = 0,
    }
    local enabled = opts.enabled ~= false
    local debugMode = opts.debugMode == true
    local host = {
        calls = calls,
        getIdentity = function()
            return {
                id = opts.id or "StandaloneTest",
                modpack = opts.modpack,
            }
        end,
        getMeta = function()
            return {
                name = opts.name or "Standalone Test",
            }
        end,
        affectsRunData = function()
            return opts.affectsRunData == true
        end,
        read = function(alias)
            if alias == "Enabled" then
                return enabled
            elseif alias == "DebugMode" then
                return debugMode
            end
            return nil
        end,
        setEnabled = function(value)
            calls.setEnabled[#calls.setEnabled + 1] = value
            if opts.setEnabledFails then
                return false, "enable boom"
            end
            enabled = value == true
            return true, nil
        end,
        setDebugMode = function(value)
            calls.setDebugMode[#calls.setDebugMode + 1] = value
            debugMode = value == true
        end,
        resync = function()
            calls.resync = calls.resync + 1
        end,
        drawTab = function()
            calls.drawTab = calls.drawTab + 1
        end,
        commitIfDirty = function()
            calls.commitIfDirty = calls.commitIfDirty + 1
            return true, nil, opts.committed == true
        end,
    }
    return host
end

local function makeImgui(opts)
    opts = opts or {}
    local calls = {
        setNextWindowSize = 0,
        begin = 0,
        endWindow = 0,
        beginMenu = 0,
        endMenu = 0,
        separator = 0,
        spacing = 0,
        checkboxLabels = {},
        buttons = {},
    }
    local checkboxValues = opts.checkboxValues or {}
    local buttonClicks = opts.buttonClicks or {}
    local imgui = {
        calls = calls,
        SetNextWindowSize = function(width, height, cond)
            calls.setNextWindowSize = calls.setNextWindowSize + 1
            calls.windowSize = { width = width, height = height, cond = cond }
        end,
        Begin = function(title, showWindow)
            calls.begin = calls.begin + 1
            calls.title = title
            calls.showWindow = showWindow
            return opts.open ~= false, opts.shouldDraw ~= false
        end,
        End = function()
            calls.endWindow = calls.endWindow + 1
        end,
        Checkbox = function(label, current)
            calls.checkboxLabels[#calls.checkboxLabels + 1] = label
            local nextValue = checkboxValues[label]
            if nextValue == nil then
                return current, false
            end
            return nextValue, true
        end,
        Button = function(label)
            calls.buttons[#calls.buttons + 1] = label
            return buttonClicks[label] == true
        end,
        Separator = function()
            calls.separator = calls.separator + 1
        end,
        Spacing = function()
            calls.spacing = calls.spacing + 1
        end,
        BeginMenu = function(label)
            calls.beginMenu = calls.beginMenu + 1
            calls.menuLabel = label
            return opts.menuOpen ~= false
        end,
        MenuItem = function(label)
            calls.menuItem = label
            return opts.menuClicked == true
        end,
        EndMenu = function()
            calls.endMenu = calls.endMenu + 1
        end,
    }
    return imgui, calls
end

function TestStandaloneHost:setUp()
    self.h = createStandaloneHarness()
    self.h:captureWarnings()
end

function TestStandaloneHost:tearDown()
    self.h:restoreWarnings()
end

function TestStandaloneHost:testErrorsWhenPluginGuidMissing()
    lu.assertErrorMsgContains("pluginGuid is required", function()
        self.h.public.standaloneHost()
    end)
end

function TestStandaloneHost:testBridgeErrorsWhenPluginGuidMissing()
    lu.assertErrorMsgContains("pluginGuid is required", function()
        self.h.public.standaloneUiBridge()
    end)
end

function TestStandaloneHost:testErrorsWhenModuleHasNoLiveHost()
    self.h:installHost(nil)

    lu.assertErrorMsgContains("no live module host is registered", function()
        self.h.public.standaloneHost(PLUGIN_GUID)
    end)
end

function TestStandaloneHost:testBridgeCallbacksNoOpBeforeRuntimeExists()
    local bridge = self.h.public.standaloneUiBridge(PLUGIN_GUID)

    local okMenu, errMenu = pcall(bridge.addMenuBar)
    local okRender, errRender = pcall(bridge.renderWindow)
    local okClosed, errClosed = pcall(bridge.handleHostGuiClosed)

    lu.assertTrue(okMenu, errMenu)
    lu.assertTrue(okRender, errRender)
    lu.assertTrue(okClosed, errClosed)
end

function TestStandaloneHost:testCreatesRuntimeWhenModuleIsNotCoordinated()
    local host = makeHost({ modpack = "standalone-pack" })
    self.h:installHost(host)
    self.h.public.coordinator.register("standalone-pack", nil)

    local runtime = self.h.public.standaloneHost(PLUGIN_GUID)

    lu.assertEquals(type(runtime.renderWindow), "function")
    lu.assertEquals(type(runtime.addMenuBar), "function")
    lu.assertEquals(type(runtime.handleHostGuiClosed), "function")
end

function TestStandaloneHost:testBridgeDispatchesInstalledRuntime()
    local bridge = self.h.public.standaloneUiBridge(PLUGIN_GUID)
    local host = makeHost({ modpack = "standalone-pack" })
    self.h:installHost(host)
    self.h.public.coordinator.register("standalone-pack", nil)
    local imgui = makeImgui({ menuClicked = true })
    self.h.rom.ImGui = imgui

    self.h.public.standaloneHost(PLUGIN_GUID)
    bridge.addMenuBar()
    bridge.renderWindow()

    lu.assertEquals(host.calls.drawTab, 1)
end

function TestStandaloneHost:testBridgeDispatchesReplacementRuntime()
    local bridge = self.h.public.standaloneUiBridge(PLUGIN_GUID)
    local firstHost = makeHost({ modpack = "standalone-pack", name = "First Standalone" })
    self.h:installHost(firstHost)
    self.h.public.coordinator.register("standalone-pack", nil)
    self.h.rom.ImGui = makeImgui({ menuClicked = true })
    self.h.public.standaloneHost(PLUGIN_GUID)
    bridge.addMenuBar()
    bridge.renderWindow()

    local secondHost = makeHost({ modpack = "standalone-pack", name = "Second Standalone" })
    self.h:installHost(secondHost)
    self.h.rom.ImGui = makeImgui({ menuClicked = true })
    self.h.public.standaloneHost(PLUGIN_GUID)
    bridge.addMenuBar()
    bridge.renderWindow()

    lu.assertEquals(firstHost.calls.drawTab, 1)
    lu.assertEquals(secondHost.calls.drawTab, 1)
end

function TestStandaloneHost:testStandaloneRuntimeReplacementClosesPreviousRuntime()
    local firstHost = makeHost({ modpack = "standalone-pack", name = "First Standalone" })
    self.h:installHost(firstHost)
    self.h.public.coordinator.register("standalone-pack", nil)
    self.h.rom.ImGui = makeImgui({ menuClicked = true })
    local firstRuntime = self.h.public.standaloneHost(PLUGIN_GUID)
    firstRuntime.addMenuBar()

    lu.assertEquals(self.h:countUiSuppressors(), 1)

    local secondHost = makeHost({ modpack = "standalone-pack", name = "Second Standalone" })
    self.h:installHost(secondHost)
    self.h.public.standaloneHost(PLUGIN_GUID)

    lu.assertEquals(self.h:countUiSuppressors(), 0)
end

function TestStandaloneHost:testStandaloneRuntimeIsRetiredWithOwningHost()
    local pluginGuid = "test-standalone-retired-with-host"
    self.h.public.coordinator.register("standalone-pack", nil)

    local firstHost = self.h:createActivatedLibHost(pluginGuid, {
        id = "StandaloneRuntimeRetire",
        name = "Standalone Runtime Retire",
    })
    local firstRuntime = self.h.public.standaloneHost(pluginGuid)
    local secondHost = self.h:createActivatedLibHost(pluginGuid, {
        id = "StandaloneRuntimeRetire",
        name = "Standalone Runtime Retire",
    })

    lu.assertNotEquals(firstHost, secondHost)
    lu.assertNil(self.h:getStandaloneRuntime(pluginGuid))
    lu.assertNotEquals(self.h:getStandaloneRuntime(pluginGuid), firstRuntime)
end

function TestStandaloneHost:testSkipsStandaloneLifecycleAndUiWhenCoordinated()
    local host = makeHost({ modpack = "standalone-pack" })
    self.h:installHost(host)
    self.h.public.coordinator.register("standalone-pack", { ModEnabled = true })
    local imgui, calls = makeImgui({ menuClicked = true })
    self.h.rom.ImGui = imgui

    local runtime = self.h.public.standaloneHost(PLUGIN_GUID)
    runtime.addMenuBar()
    runtime.renderWindow()

    lu.assertEquals(calls.beginMenu, 0)
    lu.assertEquals(calls.begin, 0)
end

function TestStandaloneHost:testFallbackMarkerHidesWhenOnlyStandaloneRuntimeIsCoordinated()
    local host = makeHost({ modpack = "standalone-pack" })
    self.h:installHost(host)
    self.h.public.coordinator.register("standalone-pack", { ModEnabled = true })

    self.h.public.standaloneHost(PLUGIN_GUID)
    local row = self.h:getFallbackMarkerRow()

    lu.assertNotNil(row)
    lu.assertFalse(row.visible())
end

function TestStandaloneHost:testFallbackMarkerShowsWhenStandaloneRuntimeIsUncoordinated()
    local host = makeHost({ modpack = "standalone-pack" })
    self.h:installHost(host)
    self.h.public.coordinator.register("standalone-pack", nil)

    self.h.public.standaloneHost(PLUGIN_GUID)
    local row = self.h:getFallbackMarkerRow()

    lu.assertNotNil(row)
    lu.assertTrue(row.visible())
end

function TestStandaloneHost:testFallbackMarkerShowsWhenAnyStandaloneRuntimeIsUncoordinated()
    local coordinatedHost = makeHost({ modpack = "standalone-pack" })
    local uncoordinatedHost = makeHost({ modpack = "other-pack" })
    self.h:installHost(coordinatedHost)
    self.h:installHost(uncoordinatedHost, "other-plugin")
    self.h.public.coordinator.register("standalone-pack", { ModEnabled = true })
    self.h.public.coordinator.register("other-pack", nil)

    self.h.public.standaloneHost(PLUGIN_GUID)
    self.h.public.standaloneHost("other-plugin")
    local row = self.h:getFallbackMarkerRow()

    lu.assertNotNil(row)
    lu.assertTrue(row.visible())
end

function TestStandaloneHost:testMenuTogglesWindowAndRenderDrawsControls()
    local host = makeHost({ modpack = "standalone-pack" })
    self.h:installHost(host)
    self.h.public.coordinator.register("standalone-pack", nil)
    local imgui, calls = makeImgui({
        menuClicked = true,
        buttonClicks = {
            ["Resync Session"] = true,
        },
    })
    self.h.rom.ImGui = imgui

    local runtime = self.h.public.standaloneHost(PLUGIN_GUID)
    runtime.addMenuBar()
    runtime.renderWindow()

    lu.assertEquals(calls.beginMenu, 1)
    lu.assertEquals(calls.menuLabel, "Standalone Test")
    lu.assertEquals(calls.menuItem, "Standalone Test")
    lu.assertEquals(calls.setNextWindowSize, 1)
    lu.assertEquals(calls.title, "Standalone Test###StandaloneTest")
    lu.assertEquals(calls.checkboxLabels, { "Enabled", "Debug Mode" })
    lu.assertEquals(host.calls.resync, 1)
    lu.assertEquals(host.calls.drawTab, 1)
    lu.assertEquals(host.calls.commitIfDirty, 1)
end

function TestStandaloneHost:testCloseFlushesRunDataAfterAffectingEnabledToggle()
    local setupCalls = 0
    self.h.game.setupRunData = function()
        setupCalls = setupCalls + 1
    end
    local host = makeHost({
        modpack = "standalone-pack",
        affectsRunData = true,
    })
    self.h:installHost(host)
    self.h.public.coordinator.register("standalone-pack", nil)
    local imgui = makeImgui({
        menuClicked = true,
        open = false,
        checkboxValues = {
            Enabled = false,
        },
    })
    self.h.rom.ImGui = imgui

    local runtime = self.h.public.standaloneHost(PLUGIN_GUID)
    runtime.addMenuBar()
    runtime.renderWindow()
    runtime.renderWindow()

    lu.assertEquals(host.calls.setEnabled, { false })
    lu.assertEquals(setupCalls, 1)
end

function TestStandaloneHost:testDebugToggleDoesNotMarkRunDataDirty()
    local setupCalls = 0
    self.h.game.setupRunData = function()
        setupCalls = setupCalls + 1
    end
    local host = makeHost({
        modpack = "standalone-pack",
        affectsRunData = true,
    })
    self.h:installHost(host)
    self.h.public.coordinator.register("standalone-pack", nil)
    local imgui = makeImgui({
        menuClicked = true,
        open = false,
        checkboxValues = {
            ["Debug Mode"] = true,
        },
    })
    self.h.rom.ImGui = imgui

    local runtime = self.h.public.standaloneHost(PLUGIN_GUID)
    runtime.addMenuBar()
    runtime.renderWindow()

    lu.assertEquals(host.calls.setDebugMode, { true })
    lu.assertEquals(setupCalls, 0)
end

function TestStandaloneHost:testStandaloneWindowSuppressesOverlaysUntilClose()
    local host = makeHost({ modpack = "standalone-pack" })
    self.h:installHost(host)
    self.h.public.coordinator.register("standalone-pack", nil)
    local imgui = makeImgui({
        menuClicked = true,
        open = false,
    })
    self.h.rom.ImGui = imgui

    local runtime = self.h.public.standaloneHost(PLUGIN_GUID)
    runtime.addMenuBar()

    lu.assertEquals(self.h:countUiSuppressors(), 1)

    runtime.renderWindow()

    lu.assertEquals(self.h:countUiSuppressors(), 0)
end

function TestStandaloneHost:testHostGuiClosedReleasesSuppressionWithoutClosingWindow()
    local host = makeHost({ modpack = "standalone-pack" })
    self.h:installHost(host)
    self.h.public.coordinator.register("standalone-pack", nil)
    local imgui = makeImgui({ menuClicked = true })
    self.h.rom.ImGui = imgui

    local runtime = self.h.public.standaloneHost(PLUGIN_GUID)
    runtime.addMenuBar()
    lu.assertEquals(self.h:countUiSuppressors(), 1)

    runtime.handleHostGuiClosed()
    lu.assertEquals(self.h:countUiSuppressors(), 0)

    runtime.renderWindow()

    lu.assertEquals(self.h:countUiSuppressors(), 1)
    lu.assertEquals(host.calls.drawTab, 1)
end
