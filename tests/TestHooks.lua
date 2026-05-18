local lu = require("luaunit")
local createLibHarness = require('tests/harness/create_lib_harness')

TestHooks = {}

local function createPathMock(target)
    local counts = {
        wrap = 0,
        override = 0,
        restore = 0,
        contextWrap = 0,
    }
    local originals = {}

    local function getEnv()
        return assert(target.env, "hook test env missing")
    end

    local testModUtil = {
        once_loaded = {
            game = function() end,
        },
        mod = {
            Path = {
                Wrap = function(path, handler)
                    counts.wrap = counts.wrap + 1
                    local env = getEnv()
                    local base = env[path]
                    env[path] = function(...)
                        return handler(base, ...)
                    end
                end,

                Override = function(path, value)
                    counts.override = counts.override + 1
                    local env = getEnv()
                    if originals[path] == nil then
                        originals[path] = env[path]
                    end
                    env[path] = value
                end,

                Restore = function(path)
                    counts.restore = counts.restore + 1
                    if originals[path] == nil then
                        error("object has no overrides")
                    end
                    getEnv()[path] = originals[path]
                    originals[path] = nil
                end,

                Context = {
                    Wrap = function(path, context)
                        counts.contextWrap = counts.contextWrap + 1
                        local env = getEnv()
                        local base = env[path]
                        env[path] = function(...)
                            context(...)
                            return base(...)
                        end
                    end,
                },
            },
        },
    }
    counts.modutil = testModUtil
    return counts, testModUtil
end

local function createSession()
    return {
        view = {},
        read = function() end,
        write = function() end,
        reset = function() end,
        getAliasSchema = function() end,
        isDirty = function()
            return false
        end,
        _flushToConfig = function() end,
        _reloadFromConfig = function() end,
        auditMismatches = function()
            return {}
        end,
    }
end

local function createStore(enabled)
    return {
        read = function(key)
            if key == "Enabled" then
                return enabled == true
            end
            return false
        end,
    }
end

function TestHooks:setUp()
    local target = {}
    self.counts, self.modutil = createPathMock(target)
    self.harness = createLibHarness({
        modutil = self.modutil,
    })
    target.env = self.harness.env
    self.env = self.harness.env
    self.public = self.harness.public
    self.hooks = self.harness.public.hooks
    self.moduleHost = self.harness.moduleHost
    self.mutation = self.harness.mutation
    self.hookRuntime = self.harness.runtime.hooks
end

function TestHooks:createHostWithHooks(pluginGuid, registerHooks, activationOpts)
    activationOpts = activationOpts or {}
    local host = self.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = self.moduleHost.prepareDefinition({}, { id = "HookTest", name = "Hook Test", storage = {} }),
        store = createStore(false),
        session = createSession(),
        registerHooks = registerHooks,
        registerIntegrations = activationOpts.registerIntegrations,
        drawTab = function() end,
    })
    return self.moduleHost.activate(host)
end

function TestHooks:testWrapRegistersOnceAndUpdatesHandler()
    self.env.AdamantHookTestWrap = function(value)
        return "base:" .. value
    end

    self:createHostWithHooks("hook-test-wrap-update", function()
        self.hooks.Wrap("AdamantHookTestWrap", function(base, value)
            return "first:" .. base(value)
        end)
        self.hooks.Wrap("AdamantHookTestWrap", function(base, value)
            return "second:" .. base(value)
        end)
    end)

    lu.assertEquals(self.counts.wrap, 1)
    lu.assertEquals(self.env.AdamantHookTestWrap("x"), "second:base:x")
end

function TestHooks:testWrapUsesInjectedModUtilWhenGlobalIsMissing()
    self.env.modutil = nil
    self.env.AdamantHookTestWrapInjected = function(value)
        return "base:" .. value
    end

    self:createHostWithHooks("hook-test-wrap-injected-modutil", function()
        self.hooks.Wrap("AdamantHookTestWrapInjected", function(base, value)
            return "wrapped:" .. base(value)
        end)
    end)

    lu.assertEquals(self.counts.wrap, 1)
    lu.assertEquals(self.env.AdamantHookTestWrapInjected("x"), "wrapped:base:x")
end

function TestHooks:testWrapRefreshOmissionFallsBackToBase()
    local pluginGuid = "hook-test-wrap-refresh"
    self.env.AdamantHookTestWrapRefresh = function(value)
        return "base:" .. value
    end

    self:createHostWithHooks(pluginGuid, function()
        self.hooks.Wrap("AdamantHookTestWrapRefresh", function(base, value)
            return "wrapped:" .. base(value)
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestWrapRefresh("x"), "wrapped:base:x")

    self:createHostWithHooks(pluginGuid, function() end)

    lu.assertEquals(self.env.AdamantHookTestWrapRefresh("x"), "base:x")
end

function TestHooks:testMissingRegisterHooksRefreshRemovesPreviousHooks()
    local pluginGuid = "hook-test-missing-register-hooks"
    self.env.AdamantHookTestMissingRegisterHooks = function(value)
        return "base:" .. value
    end

    self:createHostWithHooks(pluginGuid, function()
        self.hooks.Wrap("AdamantHookTestMissingRegisterHooks", function(base, value)
            return "wrapped:" .. base(value)
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestMissingRegisterHooks("x"), "wrapped:base:x")

    self:createHostWithHooks(pluginGuid, nil)

    lu.assertEquals(self.env.AdamantHookTestMissingRegisterHooks("x"), "base:x")
end

function TestHooks:testRetiredHookHostPrunesDeadDispatcherPluginEntries()
    local pluginGuid = "hook-test-prune-dispatcher"
    local path = "AdamantHookTestPruneDispatcher"
    self.env[path] = function(value)
        return "base:" .. value
    end

    self:createHostWithHooks(pluginGuid, function()
        self.hooks.Wrap(path, function(base, value)
            return "first:" .. base(value)
        end)
    end)
    local dispatcher = self.hookRuntime.moduleDispatchers.wrap[path]

    lu.assertNotNil(dispatcher)
    lu.assertEquals(dispatcher.pluginOrder, { pluginGuid })
    lu.assertNotNil(dispatcher.handlers[pluginGuid])
    lu.assertEquals(self.env[path]("x"), "first:base:x")

    self:createHostWithHooks(pluginGuid, nil)

    lu.assertEquals(self.env[path]("x"), "base:x")
    lu.assertEquals(dispatcher.pluginOrder, {})
    lu.assertNil(dispatcher.pluginSeen[pluginGuid])
    lu.assertNil(dispatcher.handlers[pluginGuid])
    lu.assertNil(self.hookRuntime.moduleSlots[pluginGuid])

    self:createHostWithHooks(pluginGuid, function()
        self.hooks.Wrap(path, function(base, value)
            return "second:" .. base(value)
        end)
    end)

    lu.assertEquals(self.counts.wrap, 1)
    lu.assertEquals(dispatcher.pluginOrder, { pluginGuid })
    lu.assertEquals(self.env[path]("x"), "second:base:x")
end

function TestHooks:testRetiredOverrideHostPrunesEmptyDispatcherPath()
    local pluginGuid = "hook-test-prune-override-dispatcher"
    local path = "AdamantHookTestPruneOverrideDispatcher"
    self.env[path] = function()
        return "base"
    end

    self:createHostWithHooks(pluginGuid, function()
        self.hooks.Override(path, function()
            return "override"
        end)
    end)

    lu.assertNotNil(self.hookRuntime.moduleDispatchers.override[path])
    lu.assertEquals(self.env[path](), "override")

    self:createHostWithHooks(pluginGuid, nil)

    lu.assertEquals(self.env[path](), "base")
    lu.assertNil(self.hookRuntime.moduleDispatchers.override[path])
end

function TestHooks:testRegisterHooksCanUseOwnerlessHookApi()
    local pluginGuid = "hook-test-ownerless-wrap"
    self.env.AdamantHookTestOwnerlessWrap = function(value)
        return "base:" .. value
    end

    self:createHostWithHooks(pluginGuid, function()
        self.hooks.Wrap("AdamantHookTestOwnerlessWrap", function(base, value)
            return "scoped:" .. base(value)
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestOwnerlessWrap("x"), "scoped:base:x")
end

function TestHooks:testOwnerlessHookApiRequiresActiveRegistrationContext()
    local ok = pcall(function()
        self.hooks.Wrap("AdamantHookTestNoContext", function(base)
            return base()
        end)
    end)

    lu.assertFalse(ok)
end

function TestHooks:testExplicitHookKeysMustBeNonEmptyStrings()
    lu.assertErrorMsgContains("explicit key must be a non-empty string", function()
        self:createHostWithHooks("hook-test-invalid-wrap-key", function()
            self.hooks.Wrap("AdamantHookTestInvalidWrapKey", {}, function(base)
                return base()
            end)
        end)
    end)

    lu.assertErrorMsgContains("explicit key must be a non-empty string", function()
        self:createHostWithHooks("hook-test-invalid-override-key", function()
            self.hooks.Override("AdamantHookTestInvalidOverrideKey", "", function()
                return "override"
            end)
        end)
    end)

    lu.assertErrorMsgContains("explicit key must be a non-empty string", function()
        self:createHostWithHooks("hook-test-invalid-context-key", function()
            self.hooks.Context.Wrap("AdamantHookTestInvalidContextKey", function() end, function() end)
        end)
    end)
end

function TestHooks:testOverrideRequiresFunctionReplacement()
    self.env.AdamantHookTestOverrideFunctionRequired = function()
        return "base"
    end

    local ok = pcall(function()
        self:createHostWithHooks("hook-test-override-function-required", function()
            self.hooks.Override("AdamantHookTestOverrideFunctionRequired", "not-a-function")
        end)
    end)

    lu.assertFalse(ok)
    lu.assertEquals(self.env.AdamantHookTestOverrideFunctionRequired(), "base")
end

function TestHooks:testOverrideFunctionRegistersOnceAndUpdatesReplacement()
    self.env.AdamantHookTestOverride = function()
        return "base"
    end

    self:createHostWithHooks("hook-test-override-update", function()
        self.hooks.Override("AdamantHookTestOverride", function()
            return "first"
        end)
        self.hooks.Override("AdamantHookTestOverride", function()
            return "second"
        end)
    end)

    lu.assertEquals(self.counts.override, 1)
    lu.assertEquals(self.env.AdamantHookTestOverride(), "second")
end

function TestHooks:testOverrideRefreshOmissionRestoresOriginal()
    local pluginGuid = "hook-test-override-refresh"
    self.env.AdamantHookTestOverrideRefresh = function()
        return "base"
    end

    self:createHostWithHooks(pluginGuid, function()
        self.hooks.Override("AdamantHookTestOverrideRefresh", function()
            return "override"
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestOverrideRefresh(), "override")

    self:createHostWithHooks(pluginGuid, function() end)

    lu.assertEquals(self.counts.restore, 1)
    lu.assertEquals(self.env.AdamantHookTestOverrideRefresh(), "base")
end

function TestHooks:testContextWrapRegistersOnceAndUpdatesContext()
    local observed = {}

    self.env.AdamantHookTestContext = function()
        table.insert(observed, "base")
    end

    self:createHostWithHooks("hook-test-context-update", function()
        self.hooks.Context.Wrap("AdamantHookTestContext", function()
            table.insert(observed, "first")
        end)
        self.hooks.Context.Wrap("AdamantHookTestContext", function()
            table.insert(observed, "second")
        end)
    end)

    self.env.AdamantHookTestContext()

    lu.assertEquals(self.counts.contextWrap, 1)
    lu.assertEquals(observed, { "second", "base" })
end

function TestHooks:testContextWrapRefreshOmissionBecomesInert()
    local pluginGuid = "hook-test-context-refresh"
    local observed = {}

    self.env.AdamantHookTestContextRefresh = function()
        table.insert(observed, "base")
    end

    self:createHostWithHooks(pluginGuid, function()
        self.hooks.Context.Wrap("AdamantHookTestContextRefresh", function()
            table.insert(observed, "context")
        end)
    end)

    self:createHostWithHooks(pluginGuid, function() end)
    self.env.AdamantHookTestContextRefresh()

    lu.assertEquals(observed, { "base" })
end

function TestHooks:testRefreshFailureKeepsPreviousLiveHookState()
    local pluginGuid = "hook-test-refresh-failure"
    local observed = {}

    self.env.AdamantHookTestFailureWrap = function(value)
        return "base:" .. value
    end
    self.env.AdamantHookTestFailureOverride = function()
        return "base-override"
    end
    self.env.AdamantHookTestFailureContext = function()
        table.insert(observed, "base")
    end
    self.env.AdamantHookTestFailureNew = function(value)
        return "new-base:" .. value
    end

    self:createHostWithHooks(pluginGuid, function()
        self.hooks.Wrap("AdamantHookTestFailureWrap", function(base, value)
            return "first:" .. base(value)
        end)
        self.hooks.Override("AdamantHookTestFailureOverride", function()
            return "first-override"
        end)
        self.hooks.Context.Wrap("AdamantHookTestFailureContext", function()
            table.insert(observed, "first-context")
        end)
    end)

    local ok = pcall(function()
        self:createHostWithHooks(pluginGuid, function()
            self.hooks.Wrap("AdamantHookTestFailureWrap", function(base, value)
                return "second:" .. base(value)
            end)
            self.hooks.Override("AdamantHookTestFailureOverride", function()
                return "second-override"
            end)
            self.hooks.Context.Wrap("AdamantHookTestFailureContext", function()
                table.insert(observed, "second-context")
            end)
            self.hooks.Wrap("AdamantHookTestFailureNew", function(base, value)
                return "new:" .. base(value)
            end)
            error("boom")
        end)
    end)

    observed = {}
    self.env.AdamantHookTestFailureContext()

    lu.assertFalse(ok)
    lu.assertEquals(self.counts.wrap, 1)
    lu.assertEquals(self.counts.override, 1)
    lu.assertEquals(self.counts.contextWrap, 1)
    lu.assertEquals(self.env.AdamantHookTestFailureWrap("x"), "first:base:x")
    lu.assertEquals(self.env.AdamantHookTestFailureOverride(), "first-override")
    lu.assertEquals(observed, { "first-context", "base" })
    lu.assertEquals(self.env.AdamantHookTestFailureNew("x"), "new-base:x")
    lu.assertFalse(pcall(function()
        self.hooks.Wrap("AdamantHookTestFailureNew", function(base, value)
            return "leaked:" .. base(value)
        end)
    end))
end

function TestHooks:testActivationFailureAfterHookRefreshRestoresPreviousLiveHookState()
    local pluginGuid = "hook-test-activation-rollback"
    self.env.AdamantHookTestActivationRollback = function(value)
        return "base:" .. value
    end

    self:createHostWithHooks(pluginGuid, function()
        self.hooks.Wrap("AdamantHookTestActivationRollback", function(base, value)
            return "first:" .. base(value)
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestActivationRollback("x"), "first:base:x")

    local ok = pcall(function()
        self:createHostWithHooks(pluginGuid, function()
            self.hooks.Wrap("AdamantHookTestActivationRollback", function(base, value)
                return "second:" .. base(value)
            end)
        end, {
            registerIntegrations = function()
                error("late activation boom")
            end,
        })
    end)

    lu.assertFalse(ok)
    lu.assertEquals(self.env.AdamantHookTestActivationRollback("x"), "first:base:x")
end

function TestHooks:testHookCommitFailureRemovesPartiallyInstalledCandidateSlots()
    local pluginGuid = "hook-test-partial-commit-rollback"
    local wrapPath = "AdamantHookTestPartialCommitWrap"
    local overridePath = "AdamantHookTestPartialCommitOverride"
    self.env[wrapPath] = function(value)
        return "base:" .. value
    end
    self.env[overridePath] = function()
        return "base-override"
    end

    self:createHostWithHooks(pluginGuid, function()
        self.hooks.Wrap(wrapPath, function(base, value)
            return "first:" .. base(value)
        end)
    end)

    self.counts.modutil.mod.Path.Override = function()
        error("override install boom")
    end

    local ok = pcall(function()
        self:createHostWithHooks(pluginGuid, function()
            self.hooks.Wrap(wrapPath, function(base, value)
                return "candidate:" .. base(value)
            end)
            self.hooks.Override(overridePath, function()
                return "candidate-override"
            end)
        end)
    end)

    lu.assertFalse(ok)
    lu.assertEquals(self.env[wrapPath]("x"), "first:base:x")
end

function TestHooks:testCreateModuleHostSyncsCoordinatedRuntimeImmediately()
    local packId = "hook-pack"
    local buildCalls = 0
    local target = { Value = "base" }
    self.public.coordinator.register(packId, { ModEnabled = true })

    local definition = self.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
    })
    local host = self.moduleHost.create({
        pluginGuid = "hook-pack.Alpha",
        definition = definition,
        registerPatchMutation = function(plan)
            buildCalls = buildCalls + 1
            plan:set(target, "Value", "patched")
        end,
        store = createStore(true),
        session = createSession(),
        drawTab = function() end,
    })
    self.moduleHost.activate(host)

    lu.assertEquals(buildCalls, 1)
    lu.assertEquals(target.Value, "patched")
end

function TestHooks:testCreateModuleHostHotReloadReplacesCoordinatedRuntimeState()
    local packId = "hook-reload-pack"
    local firstBuildCalls = 0
    local secondBuildCalls = 0
    local target = { Value = "base" }
    self.public.coordinator.register(packId, { ModEnabled = true })

    local store = createStore(true)

    local firstDefinition = self.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
    })
    local firstHost = self.moduleHost.create({
        pluginGuid = "hook-reload-pack.Alpha",
        definition = firstDefinition,
        registerPatchMutation = function(plan)
            firstBuildCalls = firstBuildCalls + 1
            plan:set(target, "Value", "first")
        end,
        store = store,
        session = createSession(),
        drawTab = function() end,
    })
    self.moduleHost.activate(firstHost)

    local secondDefinition = self.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
    })
    local secondHost = self.moduleHost.create({
        pluginGuid = "hook-reload-pack.Alpha",
        definition = secondDefinition,
        registerPatchMutation = function(plan)
            secondBuildCalls = secondBuildCalls + 1
            plan:set(target, "Value", "second")
        end,
        store = store,
        session = createSession(),
        drawTab = function() end,
    })
    self.moduleHost.activate(secondHost)

    lu.assertEquals(firstBuildCalls, 1)
    lu.assertEquals(secondBuildCalls, 1)
    lu.assertEquals(target.Value, "second")

    self.mutation.revertForPlugin("hook-reload-pack.Alpha", {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
    }, {
        affectsRunData = true,
        patchMutation = function(plan)
            plan:set(target, "Value", "second")
        end,
    }, nil, store)
    lu.assertEquals(target.Value, "base")
end
