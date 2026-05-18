local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestGameObject = {}

function TestGameObject:setUp()
    self.harness = createLibHarness()
    self.gameObject = self.harness.public.gameObject
end

function TestGameObject:testGetCreatesNamespacedObjectStateOnce()
    local object = {}
    local calls = 0

    local first = self.gameObject.get(object, "pack-a", "module-a", "run", function()
        calls = calls + 1
        return { Count = 1 }
    end)
    first.Count = 2

    local second = self.gameObject.get(object, "pack-a", "module-a", "run", function()
        calls = calls + 1
        return { Count = 99 }
    end)

    lu.assertEquals(calls, 1)
    lu.assertIs(first, second)
    lu.assertEquals(second.Count, 2)
    lu.assertNotNil(object._AdamantModpackLibGameObject)
end

function TestGameObject:testNamespacesPreventPackAndModuleCollisions()
    local object = {}

    local a = self.gameObject.get(object, "pack-a", "module-a", "run")
    local b = self.gameObject.get(object, "pack-a", "module-b", "run")
    local c = self.gameObject.get(object, "pack-b", "module-a", "run")

    a.Value = "a"
    b.Value = "b"
    c.Value = "c"

    lu.assertEquals(self.gameObject.peek(object, "pack-a", "module-a", "run").Value, "a")
    lu.assertEquals(self.gameObject.peek(object, "pack-a", "module-b", "run").Value, "b")
    lu.assertEquals(self.gameObject.peek(object, "pack-b", "module-a", "run").Value, "c")
end

function TestGameObject:testPeekAndClearDoNotCreateBuckets()
    local object = {}

    lu.assertNil(self.gameObject.peek(object, "pack", "module", "run"))
    lu.assertNil(object._AdamantModpackLibGameObject)
    lu.assertFalse(self.gameObject.clear(object, "pack", "module", "run"))

    self.gameObject.get(object, "pack", "module", "run")
    lu.assertNotNil(self.gameObject.peek(object, "pack", "module", "run"))
    lu.assertTrue(self.gameObject.clear(object, "pack", "module", "run"))
    lu.assertNil(self.gameObject.peek(object, "pack", "module", "run"))
    lu.assertNil(object._AdamantModpackLibGameObject)
end

function TestGameObject:testGetRejectsInvalidInputs()
    lu.assertErrorMsgContains("object must be a table", function()
        self.gameObject.get(nil, "pack", "module", "run")
    end)
    lu.assertErrorMsgContains("packId must be a non-empty string", function()
        self.gameObject.get({}, "", "module", "run")
    end)
    lu.assertErrorMsgContains("factory must return a table", function()
        self.gameObject.get({}, "pack", "module", "run", function()
            return true
        end)
    end)
end

function TestGameObject:testGetRejectsCorruptedNamespaceBuckets()
    lu.assertErrorMsgContains("root bucket is not a table", function()
        self.gameObject.get({ _AdamantModpackLibGameObject = true }, "pack", "module", "run")
    end)

    lu.assertErrorMsgContains("pack bucket is not a table", function()
        self.gameObject.get({
            _AdamantModpackLibGameObject = {
                pack = true,
            },
        }, "pack", "module", "run")
    end)

    lu.assertErrorMsgContains("module bucket is not a table", function()
        self.gameObject.get({
            _AdamantModpackLibGameObject = {
                pack = {
                    module = true,
                },
            },
        }, "pack", "module", "run")
    end)
end
