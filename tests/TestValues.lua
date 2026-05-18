local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestValues = {}

function TestValues:setUp()
    self.harness = createLibHarness()
    self.values = self.harness.values
end

function TestValues:testReadPathReturnsValueParentAndLeaf()
    local nested = {
        root = {
            child = "value",
        },
    }

    local value, parent, leaf = self.values.readPath(nested, { "root", "child" })

    lu.assertEquals(value, "value")
    lu.assertIs(parent, nested.root)
    lu.assertEquals(leaf, "child")
end

function TestValues:testReadPathHandlesMissingAndSimpleKeys()
    local tbl = {
        Enabled = true,
    }

    lu.assertEquals({ self.values.readPath(tbl, "Enabled") }, { true, tbl, "Enabled" })
    lu.assertEquals({ self.values.readPath(tbl, {}) }, { nil, nil, nil })
    lu.assertEquals({ self.values.readPath(tbl, { "missing", "child" }) }, { nil, nil, nil })
end

function TestValues:testWritePathCreatesNestedTables()
    local tbl = {}

    self.values.writePath(tbl, { "root", "child", "leaf" }, 42)

    lu.assertEquals(tbl, {
        root = {
            child = {
                leaf = 42,
            },
        },
    })
end

function TestValues:testDeepCopyPreservesCyclesWithoutSharingTables()
    local key = { name = "key" }
    local source = {
        nested = {
            value = 7,
        },
        [key] = "keyed",
    }
    source.self = source

    local copy = self.values.deepCopy(source)

    lu.assertNotIs(copy, source)
    lu.assertNotIs(copy.nested, source.nested)
    lu.assertEquals(copy.nested.value, 7)
    lu.assertIs(copy.self, copy)

    local copiedKey
    for candidate in pairs(copy) do
        if type(candidate) == "table" and candidate.name == "key" then
            copiedKey = candidate
        end
    end
    lu.assertNotNil(copiedKey)
    lu.assertNotIs(copiedKey, key)
    lu.assertEquals(copy[copiedKey], "keyed")
end

function TestValues:testDeepEqualHandlesCyclesAndDetectsMismatches()
    local a = {
        label = "same",
        nested = {
            value = 1,
        },
    }
    local b = {
        label = "same",
        nested = {
            value = 1,
        },
    }
    a.self = a
    b.self = b

    lu.assertTrue(self.values.deepEqual(a, b))

    b.nested.value = 2

    lu.assertFalse(self.values.deepEqual(a, b))
end
