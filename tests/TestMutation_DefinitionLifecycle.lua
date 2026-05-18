local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestMutation_DefinitionLifecycle = {}

local function patchMutation(fn)
    return {
        affectsRunData = true,
        patchMutation = fn,
    }
end

local function createModuleState(harness, config, definition)
    local state = harness.moduleState.create(config, definition)
    return state.store, state.session
end

function TestMutation_DefinitionLifecycle:setUp()
    self.harness = createLibHarness()
    self.public = self.harness.public.mutation
    self.mutation = self.harness.mutation
    self.moduleHost = self.harness.moduleHost
    self.hostLifecycle = self.harness.hostLifecycle
    self.coordinator = self.harness.public.coordinator
end

function TestMutation_DefinitionLifecycle:applyPlan(plan)
    return self.mutation.applyPlan(plan)
end

function TestMutation_DefinitionLifecycle:revertPlan(plan)
    return self.mutation.revertPlan(plan)
end

function TestMutation_DefinitionLifecycle:makeStore(enabled)
    return createModuleState(self.harness, { Enabled = enabled }, self.moduleHost.prepareDefinition({}, {
        id = "LifecycleStore",
        name = "Lifecycle Store",
        storage = {},
    }))
end

function TestMutation_DefinitionLifecycle:activateMutationHost(pluginGuid, definition, config, registerPatchMutation)
    local store, session = createModuleState(self.harness, config, definition)
    local _, authorHost = self.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        store = store,
        session = session,
        registerPatchMutation = registerPatchMutation,
        drawTab = function() end,
    })
    local ok, err = authorHost.tryActivate()
    return ok, err, store
end

function TestMutation_DefinitionLifecycle:testSetApplyAndRevert()
    local plan = self.public.createPlan()
    local tbl = { HP = 100 }

    plan:set(tbl, "HP", 250)

    lu.assertTrue(self:applyPlan(plan))
    lu.assertEquals(tbl.HP, 250)
    lu.assertTrue(self:revertPlan(plan))
    lu.assertEquals(tbl.HP, 100)
end

function TestMutation_DefinitionLifecycle:testSetClonesTableValue()
    local plan = self.public.createPlan()
    local replacement = { Damage = 100 }
    local tbl = { Data = { Damage = 10 } }

    plan:set(tbl, "Data", replacement)
    self:applyPlan(plan)
    replacement.Damage = 999

    lu.assertEquals(tbl.Data.Damage, 100)
    self:revertPlan(plan)
    lu.assertEquals(tbl.Data.Damage, 10)
end

function TestMutation_DefinitionLifecycle:testSetManyApplyAndRevert()
    local plan = self.public.createPlan()
    local tbl = { A = 1, B = 2, C = 3 }

    plan:setMany(tbl, { A = 10, B = 20 })
    self:applyPlan(plan)

    lu.assertEquals(tbl.A, 10)
    lu.assertEquals(tbl.B, 20)
    lu.assertEquals(tbl.C, 3)

    self:revertPlan(plan)
    lu.assertEquals(tbl.A, 1)
    lu.assertEquals(tbl.B, 2)
    lu.assertEquals(tbl.C, 3)
end

function TestMutation_DefinitionLifecycle:testTransformApplyAndRevert()
    local plan = self.public.createPlan()
    local tbl = { Requirements = { "A" } }
    local deepCopy = self.harness.rom.game.DeepCopyTable

    plan:transform(tbl, "Requirements", function(current)
        local nextValue = deepCopy(current)
        table.insert(nextValue, "B")
        return nextValue
    end)

    self:applyPlan(plan)
    lu.assertEquals(tbl.Requirements, { "A", "B" })

    self:revertPlan(plan)
    lu.assertEquals(tbl.Requirements, { "A" })
end

function TestMutation_DefinitionLifecycle:testAppendCreatesMissingListAndRestoresNil()
    local plan = self.public.createPlan()
    local tbl = {}

    plan:append(tbl, "Values", "A")
    self:applyPlan(plan)

    lu.assertEquals(tbl.Values, { "A" })

    self:revertPlan(plan)
    lu.assertNil(tbl.Values)
end

function TestMutation_DefinitionLifecycle:testAppendUniqueUsesDeepEquivalenceByDefault()
    local plan = self.public.createPlan()
    local tbl = {
        Requirements = {
            { Path = { "CurrentRun", "Hero" }, Value = 1 },
        },
    }

    plan:appendUnique(tbl, "Requirements", { Path = { "CurrentRun", "Hero" }, Value = 1 })
    self:applyPlan(plan)

    lu.assertEquals(#tbl.Requirements, 1)
    self:revertPlan(plan)
    lu.assertEquals(#tbl.Requirements, 1)
end

function TestMutation_DefinitionLifecycle:testAppendUniqueCanUseCustomComparator()
    local plan = self.public.createPlan()
    local tbl = { Values = { { Name = "A", Count = 1 } } }

    plan:appendUnique(tbl, "Values", { Name = "A", Count = 2 }, function(a, b)
        return a.Name == b.Name
    end)
    self:applyPlan(plan)

    lu.assertEquals(#tbl.Values, 1)
end

function TestMutation_DefinitionLifecycle:testApplyAndRevertAreRepeatSafe()
    local plan = self.public.createPlan()
    local tbl = { Values = {} }

    plan:append(tbl, "Values", "A")
    lu.assertTrue(self:applyPlan(plan))
    lu.assertFalse(self:applyPlan(plan))
    lu.assertEquals(tbl.Values, { "A" })

    lu.assertTrue(self:revertPlan(plan))
    lu.assertFalse(self:revertPlan(plan))
    lu.assertEquals(tbl.Values, {})
end

function TestMutation_DefinitionLifecycle:testAppendErrorsOnNonTableTarget()
    local plan = self.public.createPlan()
    local tbl = { Values = 5 }

    plan:append(tbl, "Values", "A")
    lu.assertError(function()
        self:applyPlan(plan)
    end)
end

function TestMutation_DefinitionLifecycle:testAppendUniqueDoesNotAliasInsertedTable()
    local plan = self.public.createPlan()
    local entry = { Name = "A", Meta = { Count = 1 } }
    local tbl = { Values = {} }

    plan:appendUnique(tbl, "Values", entry)
    self:applyPlan(plan)
    entry.Meta.Count = 999

    lu.assertEquals(tbl.Values[1].Meta.Count, 1)
end

function TestMutation_DefinitionLifecycle:testRemoveElementApplyAndRevert()
    local plan = self.public.createPlan()
    local tbl = { Values = { "A", "B", "C" } }

    plan:removeElement(tbl, "Values", "B")
    self:applyPlan(plan)

    lu.assertEquals(tbl.Values, { "A", "C" })

    self:revertPlan(plan)
    lu.assertEquals(tbl.Values, { "A", "B", "C" })
end

function TestMutation_DefinitionLifecycle:testRemoveElementCanUseCustomComparator()
    local plan = self.public.createPlan()
    local tbl = { Values = { { Name = "A", Count = 1 }, { Name = "B", Count = 2 } } }

    plan:removeElement(tbl, "Values", { Name = "A", Count = 999 }, function(a, b)
        return a.Name == b.Name
    end)
    self:applyPlan(plan)

    lu.assertEquals(#tbl.Values, 1)
    lu.assertEquals(tbl.Values[1].Name, "B")
end

function TestMutation_DefinitionLifecycle:testSetElementApplyAndRevert()
    local plan = self.public.createPlan()
    local tbl = { Values = { "A", "B", "C" } }

    plan:setElement(tbl, "Values", "B", "Z")
    self:applyPlan(plan)

    lu.assertEquals(tbl.Values, { "A", "Z", "C" })

    self:revertPlan(plan)
    lu.assertEquals(tbl.Values, { "A", "B", "C" })
end

function TestMutation_DefinitionLifecycle:testSetElementClonesReplacementTable()
    local plan = self.public.createPlan()
    local replacement = { Name = "Z", Meta = { Count = 10 } }
    local tbl = { Values = { { Name = "A" }, { Name = "B" } } }

    plan:setElement(tbl, "Values", { Name = "B" }, replacement, function(a, b)
        return a.Name == b.Name
    end)
    self:applyPlan(plan)
    replacement.Meta.Count = 999

    lu.assertEquals(tbl.Values[2].Name, "Z")
    lu.assertEquals(tbl.Values[2].Meta.Count, 10)
end

function TestMutation_DefinitionLifecycle:testRemoveElementErrorsOnNonTableTarget()
    local plan = self.public.createPlan()
    local tbl = { Values = 5 }

    plan:removeElement(tbl, "Values", "A")
    lu.assertError(function()
        self:applyPlan(plan)
    end)
end

function TestMutation_DefinitionLifecycle:testSetElementErrorsOnNonTableTarget()
    local plan = self.public.createPlan()
    local tbl = { Values = 5 }

    plan:setElement(tbl, "Values", "A", "B")
    lu.assertError(function()
        self:applyPlan(plan)
    end)
end

function TestMutation_DefinitionLifecycle:testAffectsRunDataIgnoresDeprecatedFlag()
    lu.assertTrue(self.mutation.affectsRunData({ affectsRunData = true }))
    lu.assertTrue(self.mutation.affectsRunData({ patchMutation = function() end }))
    lu.assertFalse(self.mutation.affectsRunData({ affectsRunData = false }))
    lu.assertFalse(self.mutation.affectsRunData({ dataMutation = true }))
    lu.assertFalse(self.mutation.affectsRunData({}))
end

function TestMutation_DefinitionLifecycle:testCommitSessionCallsSettingsObserverAfterFlush()
    local calls = 0
    local observedValue = nil
    local config = {
        Enabled = true,
        Value = false,
    }
    local definition = self.moduleHost.prepareDefinition({}, {
        id = "CommitSessionObserver",
        name = "Commit Session Observer",
        storage = {
            {
                type = "bool",
                alias = "Value",
                default = false,
            },
        },
    })
    local store, session = createModuleState(self.harness, config, definition)
    local settingsObserver = function(_, activeStore)
        calls = calls + 1
        observedValue = activeStore.read("Value")
    end

    session.write("Value", true)
    local ok, err = self.hostLifecycle.commitSession(definition, nil, settingsObserver, nil, store, session)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
    lu.assertTrue(observedValue)
    lu.assertTrue(config.Value)

    ok, err = self.hostLifecycle.commitSession(definition, nil, settingsObserver, nil, store, session)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
end

function TestMutation_DefinitionLifecycle:testCommitSessionCallsSettingsObserverForActions()
    local calls = 0
    local observedAction = nil
    local observedConfigChange = nil
    local config = {
        Enabled = true,
    }
    local definition = self.moduleHost.prepareDefinition({}, {
        id = "CommitSessionActionObserver",
        name = "Commit Session Action Observer",
        storage = {},
    })
    local store, session = createModuleState(self.harness, config, definition)
    local settingsObserver = function(_, _, commit)
        calls = calls + 1
        observedAction = commit.readAction("recording")
        observedConfigChange = commit.hadConfigChanges()
    end

    session.stageAction("recording", { kind = "start" })
    local ok, err = self.hostLifecycle.commitSession(definition, nil, settingsObserver, nil, store, session)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
    lu.assertEquals(observedAction, { kind = "start" })
    lu.assertFalse(observedConfigChange)
    lu.assertFalse(session.hasActions())
    lu.assertFalse(session.isDirty())

    ok, err = self.hostLifecycle.commitSession(definition, nil, settingsObserver, nil, store, session)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
end

function TestMutation_DefinitionLifecycle:testCommitSessionDoesNotReapplyMutationWhenPackDisabled()
    local packId = "test-pack-disabled-commit"
    self.coordinator.register(packId, { ModEnabled = false })

    local buildCalls = 0
    local target = { Value = "base" }
    local config = {
        Enabled = true,
        Value = false,
    }
    local definition = self.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "CommitSessionPackDisabled",
        name = "Commit Session Pack Disabled",
        storage = {
            {
                type = "bool",
                alias = "Value",
                default = false,
            },
        },
    })
    local store, session = createModuleState(self.harness, config, definition)
    local mutation = patchMutation(function(plan)
        buildCalls = buildCalls + 1
        plan:set(target, "Value", "patched")
    end)

    session.write("Value", true)
    local ok, err = self.hostLifecycle.commitSession(definition, mutation, nil, nil, store, session,
        "test-pack-disabled-commit")

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertTrue(config.Value)
    lu.assertEquals(buildCalls, 0)
    lu.assertEquals(target.Value, "base")
end

function TestMutation_DefinitionLifecycle:testApplyDefinitionSupportsPatchOnly()
    local store = self:makeStore(false)
    local target = { Value = 1 }
    local def = { id = "PatchOnly" }
    local pluginGuid = "test-patch-only"
    local mutation = patchMutation(function(plan)
        plan:set(target, "Value", 7)
    end)

    local ok, err = self.mutation.applyForPlugin(pluginGuid, def, mutation, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 7)

    ok, err = self.mutation.revertForPlugin(pluginGuid, def, mutation, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 1)
end

function TestMutation_DefinitionLifecycle:testPatchRuntimeSurvivesRecreatedStoreByPluginGuid()
    local target = { Value = 1 }
    local storeA = self:makeStore(true)
    local defA = {
        modpack = "test-pack",
        id = "StablePatchRuntimeA",
    }
    local mutationA = patchMutation(function(plan)
        plan:set(target, "Value", 7)
    end)

    local ok, err = self.mutation.applyForPlugin("test-stable-patch-runtime", defA, mutationA, nil, storeA)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 7)

    local storeB = self:makeStore(true)
    local defB = {
        modpack = "other-pack",
        id = "StablePatchRuntimeB",
    }
    local mutationB = patchMutation(function(plan)
        plan:set(target, "Value", 9)
    end)

    ok, err = self.mutation.applyForPlugin("test-stable-patch-runtime", defB, mutationB, nil, storeB)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 9)

    ok, err = self.mutation.revertForPlugin("test-stable-patch-runtime", defB, mutationB, nil, storeB)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 1)
end

function TestMutation_DefinitionLifecycle:testActivationSyncRevertsStablePatchWhenReloadedDisabled()
    local target = { Value = 1 }
    local pluginGuid = "test-disabled-reload-patch-runtime"
    local def = self.moduleHost.prepareDefinition({}, {
        id = "DisabledReloadPatchRuntime",
        name = "Disabled Reload Patch Runtime",
        storage = {},
    })
    local patch = function(plan)
        plan:set(target, "Value", 7)
    end

    local ok, err = self:activateMutationHost(pluginGuid, def, {
        Enabled = true,
        DebugMode = false,
    }, patch)
    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(target.Value, 7)

    ok, err = self:activateMutationHost(pluginGuid, def, {
        Enabled = false,
        DebugMode = false,
    }, patch)

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(target.Value, 1)
end

function TestMutation_DefinitionLifecycle:testApplyDefinitionNoOpsWhenLifecycleMissingAndRunDataUnaffected()
    local store = self:makeStore(false)
    local def = { id = "NoLifecycle" }
    local pluginGuid = "test-no-lifecycle"

    local ok, err = self.mutation.applyForPlugin(pluginGuid, def, nil, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)

    ok, err = self.mutation.revertForPlugin(pluginGuid, def, nil, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
end

function TestMutation_DefinitionLifecycle:testApplyDefinitionFailsWhenAffectedPatchLifecycleMissing()
    local store = self:makeStore(false)
    local def = { id = "MissingPatchLifecycle" }

    local ok, err = self.mutation.applyForPlugin("test-missing-patch-lifecycle", def,
        { affectsRunData = true }, nil, store)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "no supported mutation lifecycle found")
end

function TestMutation_DefinitionLifecycle:testApplyFailureRestoresPreviousPatchRuntime()
    local target = { Value = "base" }
    local storeA = self:makeStore(true)
    local pluginGuid = "test-restore-patch-runtime-on-apply-failure"
    local def = {
        modpack = "test-pack",
        id = "RestorePatchRuntimeOnApplyFailure",
    }
    local mutationA = patchMutation(function(plan)
        plan:set(target, "Value", "first")
    end)

    local ok, err = self.mutation.applyForPlugin(pluginGuid, def, mutationA, nil, storeA)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "first")

    local storeB = self:makeStore(true)
    local mutationB = patchMutation(function()
        error("replacement patch boom")
    end)

    ok, err = self.mutation.applyForPlugin(pluginGuid, def, mutationB, nil, storeB)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "replacement patch boom")
    lu.assertEquals(target.Value, "first")

    ok, err = self.mutation.revertForPlugin(pluginGuid, def, mutationA, nil, storeB)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "base")
end

function TestMutation_DefinitionLifecycle:testReapplyFailureRestoresPreviousPatchRuntime()
    local target = { Value = "base" }
    local store = self:makeStore(true)
    local pluginGuid = "test-restore-patch-runtime-on-reapply-failure"
    local def = {
        modpack = "test-pack",
        id = "RestorePatchRuntimeOnReapplyFailure",
    }
    local mutationA = patchMutation(function(plan)
        plan:set(target, "Value", "first")
    end)

    local ok, err = self.mutation.applyForPlugin(pluginGuid, def, mutationA, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "first")

    local mutationB = patchMutation(function()
        error("reapply patch boom")
    end)

    ok, err = self.mutation.reapplyForPlugin(pluginGuid, def, mutationB, nil, store)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "reapply patch boom")
    lu.assertEquals(target.Value, "first")

    ok, err = self.mutation.revertForPlugin(pluginGuid, def, mutationA, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "base")
end

function TestMutation_DefinitionLifecycle:testActivationSyncDisabledDoesNotBuildInactivePatch()
    local buildCalls = 0
    local pluginGuid = "test-inactive-patch-revert"
    local def = self.moduleHost.prepareDefinition({}, {
        id = "InactivePatchRevert",
        name = "Inactive Patch Revert",
        storage = {},
    })

    local ok, err = self:activateMutationHost(pluginGuid, def, {
        Enabled = false,
        DebugMode = false,
    }, function()
        buildCalls = buildCalls + 1
    end)

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(buildCalls, 0)
end

function TestMutation_DefinitionLifecycle:testSetDefinitionEnabledCommitsOnlyAfterSuccessfulEnable()
    local store = self:makeStore(false)
    local target = { Value = false }
    local def = { id = "SuccessfulEnable" }
    local mutation = patchMutation(function(plan)
        plan:set(target, "Value", true)
    end)

    local ok, err = self.hostLifecycle.setEnabled(def, mutation, nil, store, true, "test-successful-enable")

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertTrue(target.Value)
    lu.assertTrue(store.read("Enabled"))
end

function TestMutation_DefinitionLifecycle:testSetDefinitionEnabledDoesNotCommitFailedEnable()
    local store = self:makeStore(false)
    local def = { id = "FailedEnable" }
    local mutation = patchMutation(function()
        error("enable boom")
    end)

    local ok, err = self.hostLifecycle.setEnabled(def, mutation, nil, store, true, "test-failed-enable")

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "enable boom")
    lu.assertFalse(store.read("Enabled"))
end

function TestMutation_DefinitionLifecycle:testSetDefinitionEnabledReappliesWhenAlreadyEnabled()
    local store = self:makeStore(true)
    local target = { Value = 0 }
    local buildCalls = 0
    local def = { id = "ReapplyEnabled" }
    local pluginGuid = "test-reapply-enabled"
    local mutation = patchMutation(function(plan)
        buildCalls = buildCalls + 1
        plan:set(target, "Value", buildCalls)
    end)

    local ok, err = self.mutation.applyForPlugin(pluginGuid, def, mutation, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 1)

    ok, err = self.hostLifecycle.setEnabled(def, mutation, nil, store, true, pluginGuid)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(buildCalls, 2)
    lu.assertEquals(target.Value, 2)
    lu.assertTrue(store.read("Enabled"))
end

function TestMutation_DefinitionLifecycle:testSetDefinitionEnabledDisablesActivePatch()
    local store = self:makeStore(true)
    local target = { Value = "base" }
    local def = { id = "DisableActivePatch" }
    local pluginGuid = "test-disable-active-patch"
    local mutation = patchMutation(function(plan)
        plan:set(target, "Value", "patched")
    end)

    local ok, err = self.mutation.applyForPlugin(pluginGuid, def, mutation, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "patched")

    ok, err = self.hostLifecycle.setEnabled(def, mutation, nil, store, false, pluginGuid)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "base")
    lu.assertFalse(store.read("Enabled"))
end

function TestMutation_DefinitionLifecycle:testSetDefinitionEnabledNoOpsWhenAlreadyDisabled()
    local store = self:makeStore(false)
    local buildCalls = 0
    local def = { id = "AlreadyDisabled" }
    local mutation = patchMutation(function()
        buildCalls = buildCalls + 1
    end)

    local ok, err = self.hostLifecycle.setEnabled(def, mutation, nil, store, false, "test-already-disabled")

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(buildCalls, 0)
    lu.assertFalse(store.read("Enabled"))
end

function TestMutation_DefinitionLifecycle:testSetDefinitionEnabledPersistsWithoutApplyingWhenPackDisabled()
    local packId = "test-pack-disabled-enable"
    self.coordinator.register(packId, { ModEnabled = false })

    local store = self:makeStore(false)
    local target = { Value = "base" }
    local buildCalls = 0
    local def = {
        modpack = packId,
        id = "PackDisabledEnable",
    }
    local mutation = patchMutation(function(plan)
        buildCalls = buildCalls + 1
        plan:set(target, "Value", "patched")
    end)

    local ok, err = self.hostLifecycle.setEnabled(def, mutation, nil, store, true,
        "test-pack-disabled-enable")

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertTrue(store.read("Enabled"))
    lu.assertEquals(buildCalls, 0)
    lu.assertEquals(target.Value, "base")
end
