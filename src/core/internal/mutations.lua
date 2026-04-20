local internal = AdamantModpackLib_Internal
internal.mutation = internal.mutation or {}

local mutationInternal = internal.mutation
local mutationRuntime = setmetatable({}, { __mode = "k" })

---@alias MutationShape "patch"|"manual"|"hybrid"

---@class MutationInfo
---@field hasPatch boolean
---@field hasApply boolean
---@field hasRevert boolean
---@field hasManual boolean

local function GetActiveMutationPlan(store)
    local runtime = store and mutationRuntime[store]
    return runtime and runtime.plan or nil
end

local function SetActiveMutationPlan(store, plan)
    if not store then
        return
    end
    if plan == nil then
        mutationRuntime[store] = nil
        return
    end
    mutationRuntime[store] = { plan = plan }
end

local function BuildMutationPlan(def, store)
    local builder = def and def.patchPlan
    if type(builder) ~= "function" then
        return nil
    end

    local plan = public.mutation.createPlan()
    builder(plan, store)
    return plan
end

--- Infers which mutation lifecycle a module definition exposes.
---@param def ModuleDefinition Candidate module definition table.
---@return MutationShape|nil shape Inferred lifecycle shape: `patch`, `manual`, `hybrid`, or nil.
---@return MutationInfo info Flags describing which lifecycle hooks are present on the definition.
function mutationInternal.inferMutation(def)
    local hasPatch = def and type(def.patchPlan) == "function" or false
    local hasApply = def and type(def.apply) == "function" or false
    local hasRevert = def and type(def.revert) == "function" or false
    local hasManual = hasApply and hasRevert

    local inferred = nil
    if hasPatch and hasManual then
        inferred = "hybrid"
    elseif hasPatch then
        inferred = "patch"
    elseif hasManual then
        inferred = "manual"
    end

    return inferred, {
        hasPatch = hasPatch,
        hasApply = hasApply,
        hasRevert = hasRevert,
        hasManual = hasManual,
    }
end

--- Returns whether a module definition declares that it mutates live run data.
---@param def ModuleDefinition|nil Candidate module definition table.
---@return boolean mutates True when the definition opts into run-data mutation behavior.
function mutationInternal.mutatesRunData(def)
    if not def then
        return false
    end
    return def.affectsRunData == true
end

--- Applies a module definition's current mutation lifecycle to live run data.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle applied successfully.
---@return string|nil err Error message when the apply step fails.
function mutationInternal.apply(def, store)
    local inferred, info = mutationInternal.inferMutation(def)
    if not inferred then
        if not mutationInternal.mutatesRunData(def) then
            return true, nil
        end
        return false, "no supported mutation lifecycle found"
    end

    local activePlan = GetActiveMutationPlan(store)
    if activePlan then
        local okRevert, errRevert = pcall(activePlan.revert, activePlan)
        if not okRevert then
            return false, errRevert
        end
        SetActiveMutationPlan(store, nil)
    end

    local builtPlan = nil
    if info.hasPatch then
        local okBuild, result = pcall(BuildMutationPlan, def, store)
        if not okBuild then
            return false, result
        end
        builtPlan = result
        if builtPlan then
            local okApply, errApply = pcall(builtPlan.apply, builtPlan)
            if not okApply then
                return false, errApply
            end
            SetActiveMutationPlan(store, builtPlan)
        end
    end

    if info.hasManual then
        local okManual, errManual = pcall(def.apply)
        if not okManual then
            if builtPlan then
                pcall(builtPlan.revert, builtPlan)
                SetActiveMutationPlan(store, nil)
            end
            return false, errManual
        end
    end

    return true, nil
end

--- Reverts a module definition's current mutation lifecycle from live run data.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle reverted successfully.
---@return string|nil err Error message when the revert step fails.
function mutationInternal.revert(def, store)
    local inferred, info = mutationInternal.inferMutation(def)
    if not inferred then
        if not mutationInternal.mutatesRunData(def) then
            return true, nil
        end
        return false, "no supported mutation lifecycle found"
    end

    local firstErr = nil

    if info.hasManual then
        local okManual, errManual = pcall(def.revert)
        if not okManual and not firstErr then
            firstErr = errManual
        end
    end

    local activePlan = GetActiveMutationPlan(store)
    if activePlan then
        local okPlan, errPlan = pcall(activePlan.revert, activePlan)
        SetActiveMutationPlan(store, nil)
        if not okPlan and not firstErr then
            firstErr = errPlan
        end
    end

    if firstErr then
        return false, firstErr
    end

    return true, nil
end

--- Reverts and reapplies a module definition's mutation lifecycle.
---@param def ModuleDefinition Module definition declaring mutation behavior.
---@param store ManagedStore|nil Managed module store associated with the definition.
---@return boolean ok True when the mutation lifecycle reapplied successfully.
---@return string|nil err Error message when the reapply step fails.
function mutationInternal.reapply(def, store)
    local okRevert, errRevert = mutationInternal.revert(def, store)
    if not okRevert then
        return false, errRevert
    end

    local okApply, errApply = mutationInternal.apply(def, store)
    if not okApply then
        return false, errApply
    end

    return true, nil
end
