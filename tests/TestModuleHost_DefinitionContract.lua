local lu = require("luaunit")
local createModuleHostHarness = require("tests/harness/create_module_host_harness")

TestModuleHost_DefinitionContract = {}

function TestModuleHost_DefinitionContract:setUp()
    self.h = createModuleHostHarness()
    self.h:captureWarnings()
end

function TestModuleHost_DefinitionContract:tearDown()
    self.h:restoreWarnings()
end

function TestModuleHost_DefinitionContract:testCreateStoreErrorsOnUnknownTopLevelDefinitionKey()
    lu.assertErrorMsgContains("unknown definition key 'ui'", function()
        self.h:prepareDefinition({}, {
            id = "Example",
            name = "Example",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            ui = {},
        })
    end)
end

function TestModuleHost_DefinitionContract:testValidateDefinitionErrorsOnOldVocabularyKeysAsUnknown()
    lu.assertErrorMsgContains("unknown definition key 'category'", function()
        self.h:prepareDefinition({}, {
            modpack = "test-pack",
            id = "ExampleSpecial",
            name = "Example Special",
            category = "Run Mods",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
        })
    end)
end

function TestModuleHost_DefinitionContract:testPrepareDefinitionRejectsBehaviorFieldsAsUnknownKeys()
    lu.assertErrorMsgContains("unknown definition key 'affectsRunData'", function()
        self.h:prepareDefinition({}, {
            id = "Example",
            name = "Example",
            affectsRunData = true,
        })
    end)

    lu.assertErrorMsgContains("unknown definition key 'apply'", function()
        self.h:prepareDefinition({}, {
            id = "Example",
            name = "Example",
            apply = function() end,
        })
    end)
end
