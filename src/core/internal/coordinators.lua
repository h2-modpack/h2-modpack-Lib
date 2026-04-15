local internal = AdamantModpackLib_Internal
local coordinators = internal.coordinators
local coordinatorMethods = {}

function coordinatorMethods.register(packId, config)
    coordinators[packId] = config
end

function coordinatorMethods.isCoordinated(packId)
    return coordinators[packId] ~= nil
end

function coordinatorMethods.isEnabled(store, packId)
    local coord = packId and coordinators[packId]
    if coord and not coord.ModEnabled then
        return false
    end
    return store and type(store.read) == "function" and store.read("Enabled") == true or false
end

local mt = getmetatable(coordinators)
if mt == nil then
    setmetatable(coordinators, { __index = coordinatorMethods })
elseif mt.__index == nil then
    mt.__index = coordinatorMethods
elseif mt.__index ~= coordinatorMethods then
    error("internal.coordinators metatable already defines __index; cannot attach coordinator methods", 0)
end
