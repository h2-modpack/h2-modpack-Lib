local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestIntegrations = {}

function TestIntegrations:setUp()
    self.harness = createLibHarness()
    self.public = self.harness.public.integrations
    self.integrations = self.harness.integrations
end

function TestIntegrations:testRegisterAndGetIntegration()
    local api = {
        isActive = function() return true end,
    }

    local registered = self.public.register("test.example", "ProviderA", api)
    local found, providerId = self.public.get("test.example")

    lu.assertEquals(registered, api)
    lu.assertEquals(found, api)
    lu.assertEquals(providerId, "ProviderA")
end

function TestIntegrations:testRegisterReplacesSameProviderWithoutDuplicatingListEntry()
    local first = { value = 1 }
    local second = { value = 2 }

    self.public.register("test.example", "ProviderA", first)
    self.public.register("test.example", "ProviderA", second)

    local found, providerId = self.public.get("test.example")
    local providers = self.public.list("test.example")

    lu.assertEquals(found, second)
    lu.assertEquals(providerId, "ProviderA")
    lu.assertEquals(#providers, 1)
    lu.assertEquals(providers[1].api, second)
end

function TestIntegrations:testGetReturnsMostRecentlyRegisteredProvider()
    local first = { value = 1 }
    local second = { value = 2 }

    self.public.register("test.example", "ProviderA", first)
    self.public.register("test.example", "ProviderB", second)

    local found, providerId = self.public.get("test.example")

    lu.assertEquals(found, second)
    lu.assertEquals(providerId, "ProviderB")
end

function TestIntegrations:testInvokeCallsMostRecentProviderMethod()
    self.public.register("test.example", "ProviderA", {
        value = function()
            return "first"
        end,
    })
    self.public.register("test.example", "ProviderB", {
        value = function(suffix)
            return "second:" .. suffix
        end,
    })

    local result, providerId = self.public.invoke("test.example", "value", "fallback", "x")

    lu.assertEquals(result, "second:x")
    lu.assertEquals(providerId, "ProviderB")
end

function TestIntegrations:testInvokeUsesCurrentProviderAfterReregister()
    self.public.register("test.example", "ProviderA", {
        value = function()
            return "first"
        end,
    })

    lu.assertEquals(self.public.invoke("test.example", "value", "fallback"), "first")

    self.public.register("test.example", "ProviderA", {
        value = function()
            return "second"
        end,
    })

    lu.assertEquals(self.public.invoke("test.example", "value", "fallback"), "second")
end

function TestIntegrations:testInvokeReturnsFallbackForMissingProviderOrMethod()
    lu.assertEquals(self.public.invoke("test.missing", "value", "fallback"), "fallback")

    self.public.register("test.example", "ProviderA", {})

    local result, providerId = self.public.invoke("test.example", "value", "fallback")

    lu.assertEquals(result, "fallback")
    lu.assertEquals(providerId, "ProviderA")
end

function TestIntegrations:testInvokeReturnsFallbackWhenProviderMethodFails()
    local warnings = {}
    self.harness.env.print = function(message)
        warnings[#warnings + 1] = message
    end
    self.public.register("test.example", "ProviderA", {
        value = function()
            error("boom")
        end,
    })

    local result, providerId = self.public.invoke("test.example", "value", "fallback")

    lu.assertEquals(result, "fallback")
    lu.assertEquals(providerId, "ProviderA")
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "test.example.value provider 'ProviderA' failed")
end

function TestIntegrations:testListReturnsRegistrationOrder()
    self.public.register("test.example", "ProviderA", { value = 1 })
    self.public.register("test.example", "ProviderB", { value = 2 })

    local providers = self.public.list("test.example")

    lu.assertEquals(#providers, 2)
    lu.assertEquals(providers[1].providerId, "ProviderA")
    lu.assertEquals(providers[2].providerId, "ProviderB")
end

function TestIntegrations:testUnregisterRemovesOneProvider()
    local first = { value = 1 }
    local second = { value = 2 }

    self.public.register("test.example", "ProviderA", first)
    self.public.register("test.example", "ProviderB", second)

    lu.assertTrue(self.public.unregister("test.example", "ProviderB"))

    local found, providerId = self.public.get("test.example")
    local providers = self.public.list("test.example")

    lu.assertEquals(found, first)
    lu.assertEquals(providerId, "ProviderA")
    lu.assertEquals(#providers, 1)
end

function TestIntegrations:testUnregisterProviderRemovesProviderAcrossIntegrationIds()
    self.public.register("test.one", "ProviderA", { value = 1 })
    self.public.register("test.two", "ProviderA", { value = 2 })
    self.public.register("test.two", "ProviderB", { value = 3 })

    local removed = self.public.unregisterProvider("ProviderA")

    lu.assertEquals(removed, 2)
    lu.assertNil(self.public.get("test.one"))

    local found, providerId = self.public.get("test.two")
    lu.assertEquals(found.value, 3)
    lu.assertEquals(providerId, "ProviderB")
end

function TestIntegrations:testHostInstallStagesProvidersUntilCommit()
    local id = "test.host.stage"
    local providerId = "StagedProvider"
    local previous = { value = "previous" }
    local replacement = { value = "replacement" }
    self.public.register(id, providerId, previous)
    local definition = self.harness.moduleHost.prepareDefinition({}, {
        id = "IntegrationStageHost",
        name = "Integration Stage Host",
        storage = {},
    })
    local state = self.harness.moduleState.create({}, definition)
    local host = self.harness.moduleHost.create({
        pluginGuid = "integration-stage-host",
        definition = definition,
        store = state.store,
        session = state.session,
        drawTab = function() end,
    })

    local observedDuringInstall = nil
    local receipt = self.integrations.installForHost(host, function()
        self.public.register(id, providerId, replacement)
        observedDuringInstall = self.public.get(id)
    end)

    lu.assertEquals(observedDuringInstall, previous)
    lu.assertEquals(self.public.get(id), previous)

    local ok, err = receipt.commit()
    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(self.public.get(id), replacement)

    ok, err = receipt.dispose()
    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(self.public.get(id), previous)
end

function TestIntegrations:testMissingIntegrationReturnsNilAndEmptyList()
    local found, providerId = self.public.get("test.missing")
    local providers = self.public.list("test.missing")

    lu.assertNil(found)
    lu.assertNil(providerId)
    lu.assertEquals(providers, {})
end
