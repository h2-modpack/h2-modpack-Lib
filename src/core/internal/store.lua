local internal = AdamantModpackLib_Internal

internal.store = internal.store or {}

local StoreState = setmetatable({}, { __mode = "k" })

--- Registers internal callbacks for a managed store object.
---@param store ManagedStore
---@param state table
function internal.store.bindManagedStore(store, state)
    StoreState[store] = state
end

--- Writes a persisted storage value through a managed store.
--- Internal plumbing only; ordinary state changes should go through session.
---@param store ManagedStore
---@param keyOrAlias string|table Alias, config key, or nested config path to write.
---@param value any Value to persist, normalized through the owning storage type when applicable.
function internal.store.writePersisted(store, keyOrAlias, value)
    local state = store and StoreState[store] or nil
    if not state or type(state.write) ~= "function" then
        error("internal.store.writePersisted expects a managed store", 2)
    end
    return state.write(keyOrAlias, value)
end

---@param store ManagedStore
---@param alias string
---@return table[]
function internal.store.getPackedAliases(store, alias)
    local state = store and StoreState[store] or nil
    if not state or type(state.getPackedAliases) ~= "function" then
        return {}
    end
    return state.getPackedAliases(alias)
end
