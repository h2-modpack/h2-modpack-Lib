local createLibHarness = require("tests/harness/create_lib_harness")

local function createModUtilMock()
    return {
        once_loaded = {
            game = function() end,
        },
        mod = {
            Path = {
                Wrap = function() end,
                Override = function() end,
                Restore = function() end,
                Context = {
                    Wrap = function() end,
                },
            },
        },
    }
end

local function createGameState(opts)
    opts = opts or {}
    local game = {
        screenData = opts.ScreenData or {
            HUD = {
                ComponentData = {},
            },
        },
        hudScreen = opts.HUDScreen or {
            Components = {},
        },
        showingCombatUI = opts.ShowingCombatUI ~= false,
        nextComponentId = opts.nextComponentId or 100,
        modifyTextBox = opts.ModifyTextBox or function() end,
        setAlpha = opts.SetAlpha or function() end,
        destroy = opts.Destroy or function() end,
    }

    game.createComponentFromData = opts.CreateComponentFromData or function(_, data)
        game.nextComponentId = game.nextComponentId + 1
        return {
            Id = game.nextComponentId,
            Name = data.Name,
        }
    end

    return game
end

local function createGameDeps(game)
    return {
        runData = {
            SetupRunData = function() end,
        },
        overlays = {
            ScreenData = function()
                return game.screenData
            end,
            HUDScreen = function()
                return game.hudScreen
            end,
            ShowingCombatUI = function()
                return game.showingCombatUI
            end,
            ModifyTextBox = function(args)
                return game.modifyTextBox(args)
            end,
            SetAlpha = function(args)
                return game.setAlpha(args)
            end,
            CreateComponentFromData = function(componentData, data)
                return game.createComponentFromData(componentData, data)
            end,
            Destroy = function(args)
                return game.destroy(args)
            end,
        },
    }
end

local function createModuleState(base, config, definition)
    local state = base.moduleState.create(config, definition)
    return state.store, state.session
end

local function createOverlayHarness(opts)
    opts = opts or {}
    local game = createGameState(opts)
    local modutil = opts.modutil or createModUtilMock()
    local base = createLibHarness({
        config = opts.config,
        public = opts.public,
        runtime = opts.runtime,
        plugin = opts.plugin,
        rom = opts.rom,
        chalk = opts.chalk,
        modutil = modutil,
        gameDeps = opts.gameDeps or createGameDeps(game),
        importOverrides = opts.importOverrides,
    })

    return {
        harness = base,
        public = base.public,
        overlayPublic = base.public.overlays,
        config = base.config,
        runtime = base.runtime,
        overlayState = base.runtime.overlays,
        rendererState = base.runtime.overlays.renderer,
        retainedState = base.runtime.overlays.retained,
        overlays = base.overlays,
        moduleHost = base.moduleHost,
        moduleState = base.moduleState,
        game = game,
        modutil = modutil,

        createModuleState = function(config, definition)
            return createModuleState(base, config, definition)
        end,

        createHostWithOverlays = function(pluginGuid, registerOverlays, hostOpts)
            hostOpts = hostOpts or {}
            local definition = base.moduleHost.prepareDefinition({}, {
                id = hostOpts.id or "OverlayHost",
                name = hostOpts.name or "Overlay Host",
                storage = hostOpts.storage or {},
            })
            local store, session = createModuleState(base, hostOpts.config or {
                Enabled = true,
                DebugMode = false,
            }, definition)
            local host, authorHost = base.moduleHost.create({
                pluginGuid = pluginGuid,
                definition = definition,
                store = store,
                session = session,
                registerOverlays = registerOverlays,
                onSettingsCommitted = hostOpts.onSettingsCommitted,
                registerIntegrations = hostOpts.registerIntegrations,
                drawTab = function() end,
            })
            return host, authorHost, store, session, definition
        end,
    }
end

return createOverlayHarness
