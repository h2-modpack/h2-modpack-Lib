local deps = ...

local runtime = deps.runtime
runtime.moduleHost = runtime.moduleHost or {}

-- Hot-reload-stable host lifecycle anchors. Live hosts and their weak state are
-- used to retire prior side-effect receipts when a replacement host activates.
runtime.moduleHost.liveHosts = runtime.moduleHost.liveHosts or {}
runtime.moduleHost.pendingCoordinatorRebuilds = runtime.moduleHost.pendingCoordinatorRebuilds
    or setmetatable({}, { __mode = "k" })
runtime.moduleHost.hostState = runtime.moduleHost.hostState or setmetatable({}, { __mode = "k" })

local liveHosts = runtime.moduleHost.liveHosts
local pendingCoordinatorRebuilds = runtime.moduleHost.pendingCoordinatorRebuilds
local HostState = runtime.moduleHost.hostState

local hostState = {}

function hostState.get(host)
    return type(host) == "table" and HostState[host] or nil
end

function hostState.set(host, state)
    HostState[host] = state
end

function hostState.getLiveHost(pluginGuid)
    return type(pluginGuid) == "string" and pluginGuid ~= "" and liveHosts[pluginGuid] or nil
end

function hostState.setLiveHost(pluginGuid, host)
    liveHosts[pluginGuid] = host
end

function hostState.getPendingCoordinatorRebuild(definition)
    return pendingCoordinatorRebuilds[definition]
end

function hostState.setPendingCoordinatorRebuild(definition, rebuild)
    pendingCoordinatorRebuilds[definition] = rebuild
end

return hostState
