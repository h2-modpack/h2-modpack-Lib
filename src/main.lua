-- =============================================================================
-- ADAMANT-LIB: Shared utilities for adamant standalone mods
-- =============================================================================
-- Access via: local lib = rom.mods['adamant-Lib'].public
--
-- Provides:
--   backup, restore = lib.createBackupSystem()
--   lib.standaloneUI(definition, config, apply, restore)

local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN

--- Create an isolated backup/restore pair.
--- Each mod gets its own state — no collision between mods.
--- backup() accepts variadic keys: backup(tbl, "k1", "k2", ...)
--- @return function backup
--- @return function restore
function public.createBackupSystem()
    local NIL = {}
    local savedValues = {}

    local function backup(tbl, ...)
        savedValues[tbl] = savedValues[tbl] or {}
        local saved = savedValues[tbl]
        for _, key in ipairs({...}) do
            if saved[key] == nil then
                local v = tbl[key]
                saved[key] = (v == nil) and NIL or (type(v) == "table" and DeepCopyTable(v) or v)
            end
        end
    end

    local function restore()
        for tbl, keys in pairs(savedValues) do
            for key, v in pairs(keys) do
                if v == NIL then
                    tbl[key] = nil
                elseif type(v) == "table" then
                    tbl[key] = DeepCopyTable(v)
                else
                    tbl[key] = v
                end
            end
        end
    end

    return backup, restore
end

--- Register the standalone menu-bar UI for a boolean mod.
--- Skips rendering when adamant-Core is installed.
--- Reads def.dataMutation to decide whether to call SetupRunData() after toggle.
--- @param def table         public.definition (needs .name, .tooltip, .dataMutation)
--- @param modConfig table   the mod's chalk config (needs .Enabled)
--- @param apply function    called on enable
--- @param restoreFn function called on disable
function public.standaloneUI(def, modConfig, apply, restoreFn)
    rom.gui.add_to_menu_bar(function()
        if mods['adamant-Core'] then return end
        if rom.ImGui.BeginMenu("adamant") then
            local val, chg = rom.ImGui.Checkbox(def.name, modConfig.Enabled)
            if chg then
                modConfig.Enabled = val
                if val then apply() else restoreFn() end
                if def.dataMutation then SetupRunData() end
            end
            if rom.ImGui.IsItemHovered() and (def.tooltip or "") ~= "" then
                rom.ImGui.SetTooltip(def.tooltip)
            end
            rom.ImGui.EndMenu()
        end
    end)
end
