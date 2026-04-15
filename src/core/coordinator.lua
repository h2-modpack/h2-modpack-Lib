local internal = AdamantModpackLib_Internal
local coordinatorInternal = internal.coordinators
public.coordinator = public.coordinator or {}
local coordinator = public.coordinator

--- Registers coordinator metadata for a coordinated module pack.
---@param packId string Unique coordinator pack identifier.
---@param config table Coordinator configuration table.
function coordinator.register(packId, config)
    return coordinatorInternal.register(packId, config)
end

--- Returns whether a pack id has coordinator metadata registered.
---@param packId string Unique coordinator pack identifier.
---@return boolean coordinated True when the pack id is registered with the coordinator.
function coordinator.isCoordinated(packId)
    return coordinatorInternal.isCoordinated(packId)
end

--- Returns whether a coordinated or standalone module should currently be treated as enabled.
---@param store table|nil Managed module store to read the Enabled flag from.
---@param packId string|nil Unique coordinator pack identifier.
---@return boolean enabled True when the module should be considered enabled.
function coordinator.isEnabled(store, packId)
    return coordinatorInternal.isEnabled(store, packId)
end
