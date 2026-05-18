local deps = ...

local rom = deps.rom
local gameDeps = {
    runData = {
        SetupRunData = function()
            return rom.game.SetupRunData()
        end,
    },

    overlays = {
        ScreenData = function()
            return ScreenData
        end,

        HUDScreen = function()
            return HUDScreen
        end,

        ShowingCombatUI = function()
            return ShowingCombatUI
        end,

        ModifyTextBox = function(args)
            return ModifyTextBox(args)
        end,

        SetAlpha = function(args)
            return SetAlpha(args)
        end,

        CreateComponentFromData = function(componentData, data)
            return CreateComponentFromData(componentData, data)
        end,

        Destroy = function(args)
            return Destroy(args)
        end,
    },
}

return gameDeps
