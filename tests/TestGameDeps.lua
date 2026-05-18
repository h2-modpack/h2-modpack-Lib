local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestGameDeps = {}

function TestGameDeps:setUp()
    self.calls = {}
    self.harness = createLibHarness({
        ScreenData = {
            HUD = {
                ComponentData = {},
            },
        },
        HUDScreen = {
            Components = {},
        },
        ShowingCombatUI = true,
        ModifyTextBox = function(args)
            self.calls.modifyTextBox = args
            return "modified"
        end,
        SetAlpha = function(args)
            self.calls.setAlpha = args
            return "alpha"
        end,
        CreateComponentFromData = function(componentData, data)
            self.calls.createComponentFromData = {
                componentData = componentData,
                data = data,
            }
            return {
                Id = data.Id,
            }
        end,
        Destroy = function(args)
            self.calls.destroy = args
            return "destroyed"
        end,
    })
    self.gameDeps = self.harness.gameDeps
end

function TestGameDeps:testGameGlobalsAreLateReadFromHarnessEnvironment()
    lu.assertIs(self.gameDeps.overlays.ScreenData(), self.harness.env.ScreenData)
    lu.assertIs(self.gameDeps.overlays.HUDScreen(), self.harness.env.HUDScreen)
    lu.assertEquals(self.gameDeps.overlays.ShowingCombatUI(), true)

    local replacementScreenData = {
        HUD = {
            ComponentData = {
                Changed = true,
            },
        },
    }
    self.harness.env.ScreenData = replacementScreenData
    self.harness.env.ShowingCombatUI = false

    lu.assertIs(self.gameDeps.overlays.ScreenData(), replacementScreenData)
    lu.assertEquals(self.gameDeps.overlays.ShowingCombatUI(), false)
end

function TestGameDeps:testSetupRunDataUsesRomGameBoundary()
    local count = 0
    self.harness.rom.game.SetupRunData = function()
        count = count + 1
        return "setup"
    end

    lu.assertEquals(self.gameDeps.runData.SetupRunData(), "setup")
    lu.assertEquals(count, 1)
end

function TestGameDeps:testOverlayFunctionsDelegateToHarnessEnvironment()
    local componentData = {}
    local data = {
        Id = 42,
    }

    lu.assertEquals(self.gameDeps.overlays.ModifyTextBox({ Id = 1, Text = "Ready" }), "modified")
    lu.assertEquals(self.gameDeps.overlays.SetAlpha({ Id = 1, Fraction = 0.5 }), "alpha")
    lu.assertEquals(self.gameDeps.overlays.Destroy({ Id = 1 }), "destroyed")
    lu.assertEquals(self.gameDeps.overlays.CreateComponentFromData(componentData, data), { Id = 42 })

    lu.assertEquals(self.calls.modifyTextBox, { Id = 1, Text = "Ready" })
    lu.assertEquals(self.calls.setAlpha, { Id = 1, Fraction = 0.5 })
    lu.assertEquals(self.calls.destroy, { Id = 1 })
    lu.assertIs(self.calls.createComponentFromData.componentData, componentData)
    lu.assertIs(self.calls.createComponentFromData.data, data)
end
