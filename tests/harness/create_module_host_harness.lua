local createLibHarness = require("tests/harness/create_lib_harness")

local function createModuleHostHarness(harnessOpts)
    local base = createLibHarness(harnessOpts)
    local h = {
        harness = base,
        public = base.public,
        config = base.config,
        runtime = base.runtime,
        rom = base.rom,
        moduleHost = base.moduleHost,
        moduleState = base.moduleState,
        hostLifecycle = base.hostLifecycle,
        hostState = base.hostState,
        coordinator = base.coordinator,
        integrations = base.integrations,
        overlays = base.overlays,
        standalone = base.standalone,
        warnings = {},
    }

    function h:captureWarnings()
        self.warnings = {}
        self.config.DebugMode = true
        self.previousPrint = self.harness.env.print
        self.harness.env.print = function(msg)
            self.warnings[#self.warnings + 1] = msg
        end
    end

    function h:restoreWarnings()
        self.config.DebugMode = false
        self.harness.env.print = self.previousPrint
        self.previousPrint = nil
    end

    function h:prepareDefinition(owner, definition, structuralOpts)
        return self.moduleHost.prepareDefinition(owner or {}, definition, structuralOpts)
    end

    function h:createModuleState(config, definition)
        local state = self.moduleState.create(config, definition)
        return state.store, state.session
    end

    function h:createHost(pluginGuid, hostOpts, activationOpts)
        hostOpts = hostOpts or {}
        activationOpts = activationOpts or {}
        return self.moduleHost.create({
            pluginGuid = pluginGuid,
            definition = hostOpts.definition,
            store = hostOpts.store,
            session = hostOpts.session,
            registerHooks = activationOpts.registerHooks or hostOpts.registerHooks,
            registerPatchMutation = hostOpts.registerPatchMutation,
            onSettingsCommitted = hostOpts.onSettingsCommitted,
            registerIntegrations = activationOpts.registerIntegrations or hostOpts.registerIntegrations,
            registerOverlays = activationOpts.registerOverlays or hostOpts.registerOverlays,
            drawTab = hostOpts.drawTab,
            drawQuickContent = hostOpts.drawQuickContent,
        })
    end

    function h:createActivatedHost(pluginGuid, hostOpts, activationOpts)
        local host, authorHost = self:createHost(pluginGuid, hostOpts, activationOpts)
        local ok, err = authorHost.tryActivate()
        return host, authorHost, ok, err
    end

    function h:createPreparedStore(config, rawDefinition)
        local definition = self:prepareDefinition({}, rawDefinition)
        local store, session = self:createModuleState(config, definition)
        return definition, store, session
    end

    function h:liveHost(pluginGuid)
        return self.public.getLiveModuleHost(pluginGuid)
    end

    return h
end

return createModuleHostHarness
