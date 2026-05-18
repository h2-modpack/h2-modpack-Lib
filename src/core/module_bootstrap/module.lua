local deps = ...

local logging = deps.logging
local moduleHost = deps.moduleHost
local moduleState = deps.moduleState

---@class ModuleCreateOpts
---@field pluginGuid string
---@field config table
---@field definition ModuleDefinition
---@field registerHooks fun(host: AuthorHost, store: ManagedStore)|nil
---@field registerPatchMutation fun(plan: table, host: AuthorHost, store: ManagedStore)|nil
---@field onSettingsCommitted fun(host: AuthorHost, store: ManagedStore, commit: table)|nil
---@field registerIntegrations fun(host: AuthorHost, store: ManagedStore)|nil
---@field registerOverlays fun(overlays: table, host: AuthorHost, store: ManagedStore)|nil
---@field drawTab fun(imgui: table, session: AuthorSession, host: AuthorHost)
---@field drawQuickContent fun(imgui: table, session: AuthorSession, host: AuthorHost)|nil

local KnownModuleOpts = {
    pluginGuid = true,
    config = true,
    definition = true,
    registerHooks = true,
    registerPatchMutation = true,
    onSettingsCommitted = true,
    registerIntegrations = true,
    registerOverlays = true,
    drawTab = true,
    drawQuickContent = true,
}

local function ValidateKnownOpts(opts)
    for key in pairs(opts) do
        if not KnownModuleOpts[key] then
            logging.violate("host.unknown_opt", "createModule: unknown option '%s'", tostring(key))
        end
    end
end

local function GetStructuralBaseline(pluginGuid)
    local previousHost = moduleHost.getLiveHost(pluginGuid)
    local previousState = moduleHost.getState(previousHost)
    local previousDefinition = previousState and previousState.definition or nil
    local previousFingerprint = previousDefinition and previousDefinition._structuralFingerprint or nil
    if previousFingerprint == nil then
        return nil
    end
    return {
        _definitionStructuralFingerprint = previousFingerprint,
    }
end

--- Creates a module through the canonical prepare -> store -> host pipeline.
--- Call `host.tryActivate()` after construction.
---@param opts ModuleCreateOpts
---@return AuthorHost host
---@return ManagedStore store
function public.createModule(opts)
    if type(opts) ~= "table" then
        logging.violate("host.invalid_create_opts", "createModule: opts must be a table")
    end
    ValidateKnownOpts(opts)
    if type(opts.config) ~= "table" then
        logging.violate("host.invalid_create_opts", "createModule: config is required")
    end
    if type(opts.pluginGuid) ~= "string" or opts.pluginGuid == "" then
        logging.violate("host.invalid_create_opts", "createModule: pluginGuid is required")
    end

    local definition = moduleHost.prepareDefinition(GetStructuralBaseline(opts.pluginGuid), opts.definition, {
        hasQuickContent = type(opts.drawQuickContent) == "function",
    })
    local state = moduleState.create(opts.config, definition)
    local store = state.store
    local session = state.session
    local _, authorHost = moduleHost.create({
        definition = definition,
        pluginGuid = opts.pluginGuid,
        store = store,
        session = session,
        registerHooks = opts.registerHooks,
        registerPatchMutation = opts.registerPatchMutation,
        onSettingsCommitted = opts.onSettingsCommitted,
        registerIntegrations = opts.registerIntegrations,
        registerOverlays = opts.registerOverlays,
        drawTab = opts.drawTab,
        drawQuickContent = opts.drawQuickContent,
    })
    return authorHost, store
end

--- Safely creates a module through the canonical prepare -> store -> host pipeline.
--- Returns nils plus the construction error instead of throwing.
---@param opts ModuleCreateOpts
---@return AuthorHost|nil host
---@return ManagedStore|nil store
---@return string|nil err
function public.tryCreateModule(opts)
    local ok, host, store = pcall(public.createModule, opts)
    if ok then
        return host, store, nil
    end

    local err = tostring(host)
    logging.violate("host.create_failed", "createModule failed; skipping module: %s", err)
    return nil, nil, err
end
