local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestStorageValidation = {}

local function prepareDefinition(harness, definition)
    return harness.moduleHost.prepareDefinition({}, definition)
end

local function createModuleState(harness, config, definition)
    local state = harness.moduleState.create(config, definition)
    return state.store, state.session
end

function TestStorageValidation:setUp()
    self.harness = createLibHarness()
    self.storage = self.harness.storage
    self.hashing = assert(self.harness.public.hashing, "hashing public surface missing")
end

function TestStorageValidation:tearDown()
    self.harness = nil
    self.storage = nil
    self.hashing = nil
end

function TestStorageValidation:testDuplicateAliasFails()
    lu.assertErrorMsgContains("duplicate alias 'Flag'", function()
        self.storage.validate({
            { type = "bool", alias = "Flag", default = false },
            { type = "bool", alias = "Flag", default = false },
        }, "DuplicateAlias")
    end)
end

function TestStorageValidation:testInvalidRootAliasFails()
    lu.assertErrorMsgContains("alias 'Bad-Alias' must start with a letter", function()
        self.storage.validate({
            { type = "bool", alias = "Bad-Alias", default = false },
        }, "InvalidRootAlias")
    end)
end

function TestStorageValidation:testInvalidPackedChildAliasFails()
    lu.assertErrorMsgContains("alias 'Bad.Child' must start with a letter", function()
        self.storage.validate({
            {
                type = "packedInt",
                alias = "Packed",
                bits = {
                    { alias = "Bad.Child", offset = 0, width = 1, type = "bool", default = false },
                },
            },
        }, "InvalidPackedChildAlias")
    end)
end

function TestStorageValidation:testInvalidTableRowAliasFails()
    lu.assertErrorMsgContains("alias 'Bad=Row' must start with a letter", function()
        self.storage.validate({
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "bool", alias = "Bad=Row", default = false },
                },
            },
        }, "InvalidTableRowAlias")
    end)
end

function TestStorageValidation:testTransientRootRegistersAliasButNotPersistedRoots()
    local storage = {
        { type = "bool", alias = "Enabled", default = false },
        { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
    }

    self.storage.validate(storage, "TransientRoot")

    lu.assertEquals(#self.storage.getRoots(storage), 1)
    lu.assertEquals(self.storage.getRoots(storage)[1].alias, "Enabled")
    lu.assertNotNil(self.storage.getAliases(storage).FilterText)
end

function TestStorageValidation:testRuntimeCacheRootRegistersAliasButNotHashRoot()
    local storage = {
        { type = "bool", alias = "Enabled", default = false },
        { type = "bool", alias = "RecordingArmed", default = false, stage = false, hash = false },
    }

    self.storage.validate(storage, "RuntimeCacheRoot")

    lu.assertEquals(#self.storage.getRoots(storage), 1)
    lu.assertEquals(self.storage.getRoots(storage)[1].alias, "Enabled")
    lu.assertNotNil(self.storage.getAliases(storage).RecordingArmed)
    lu.assertEquals(#self.storage.getRuntimeCacheRoots(storage), 1)
end

function TestStorageValidation:testRuntimePackedIntFails()
    lu.assertErrorMsgContains("stage=false packedInt roots are not supported", function()
        self.storage.validate({
            {
                type = "packedInt",
                alias = "RuntimePacked",
                stage = false,
                hash = false,
                bits = {
                    { alias = "Bit", offset = 0, width = 1, type = "bool", default = false },
                },
            },
        }, "RuntimePacked")
    end)
end

function TestStorageValidation:testUnknownRootStorageFieldFails()
    lu.assertErrorMsgContains("storage.unknown_field", function()
        self.storage.validate({
            { type = "int", alias = "Count", default = 0, min = 0, max = 10, defalt = 1 },
        }, "UnknownRootField")
    end)
end

function TestStorageValidation:testUnknownFieldForStorageTypeFails()
    lu.assertErrorMsgContains("storage.unknown_field", function()
        self.storage.validate({
            { type = "bool", alias = "Flag", default = false, width = 1 },
        }, "UnknownTypeField")
    end)
end

function TestStorageValidation:testUnknownPackedBitFieldFails()
    lu.assertErrorMsgContains("storage.unknown_field", function()
        self.storage.validate({
            {
                type = "packedInt",
                alias = "Packed",
                bits = {
                    { alias = "Bit", offset = 0, width = 1, type = "bool", default = false, defalt = true },
                },
            },
        }, "UnknownPackedBitField")
    end)
end

function TestStorageValidation:testUnknownTableRowFieldFails()
    lu.assertErrorMsgContains("storage.unknown_field", function()
        self.storage.validate({
            {
                type = "table",
                alias = "Rows",
                defaultRows = 1,
                row = {
                    { type = "int", alias = "Count", default = 0, min = 0, max = 10, with = 4 },
                },
            },
        }, "UnknownTableRowField")
    end)
end

function TestStorageValidation:testPackedIntDerivesChildAliasesAndDefault()
    local storage = {
        {
            type = "packedInt",
            alias = "Packed",
            bits = {
                { alias = "EnabledBit", offset = 0, width = 1, type = "bool", default = true },
                { alias = "ModeBits", offset = 1, width = 2, type = "int", default = 2 },
            },
        },
    }

    self.storage.validate(storage, "PackedTest")

    lu.assertEquals(storage[1].default, 5)
    lu.assertNotNil(self.storage.getAliases(storage).EnabledBit)
    lu.assertNotNil(self.storage.getAliases(storage).ModeBits)
end

function TestStorageValidation:testResetSessionToDefaultsResetsChangedPersistentRoots()
    local config = { Flag = true, Count = 3, Filter = "ignored" }
    local definition = prepareDefinition(self.harness, {
        id = "ResetPersistentRoots",
        name = "Reset Persistent Roots",
        storage = {
            { type = "bool", alias = "Flag", default = false },
            { type = "int", alias = "Count", default = 1, min = 0, max = 5 },
            { type = "string", alias = "Filter", persist = false, hash = false, default = "", maxLen = 32 },
        },
    })
    local _, session = createModuleState(self.harness, config, definition)

    session.write("Filter", "live")
    local changed, count = self.harness.public.resetStorageToDefaults(definition.storage, session)

    lu.assertTrue(changed)
    lu.assertEquals(count, 2)
    lu.assertFalse(session.read("Flag"))
    lu.assertEquals(session.read("Count"), 1)
    lu.assertEquals(session.read("Filter"), "live")
end

function TestStorageValidation:testResetSessionToDefaultsCanExcludeAliases()
    local config = { Flag = true, ViewRegion = "Surface" }
    local definition = prepareDefinition(self.harness, {
        id = "ResetExcludeAliases",
        name = "Reset Exclude Aliases",
        storage = {
            { type = "bool", alias = "Flag", default = false },
            { type = "string", alias = "ViewRegion", default = "Underworld" },
        },
    })
    local _, session = createModuleState(self.harness, config, definition)

    local changed, count = self.harness.public.resetStorageToDefaults(definition.storage, session, {
        exclude = { ViewRegion = true },
    })

    lu.assertTrue(changed)
    lu.assertEquals(count, 1)
    lu.assertFalse(session.read("Flag"))
    lu.assertEquals(session.read("ViewRegion"), "Surface")
end
