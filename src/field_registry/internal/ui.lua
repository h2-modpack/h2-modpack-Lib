local internal = AdamantModpackLib_Internal
local ui = internal.ui
local libWarn = internal.logging.warnIf
local WidgetTypes = public.registry.widgets
local LayoutTypes = public.registry.layouts
local widgetHelpers = public.registry.widgetHelpers

local function KeyStr(key)
    if type(key) == "table" then
        return table.concat(key, ".")
    end
    return tostring(key)
end

ui.StorageKey = KeyStr

local function NormalizeInteger(node, value)
    local num = tonumber(value)
    if num == nil then
        num = tonumber(node.default) or 0
    end
    num = math.floor(num)
    if node.min ~= nil and num < node.min then num = node.min end
    if node.max ~= nil and num > node.max then num = node.max end
    return num
end

ui.NormalizeInteger = NormalizeInteger

local function NormalizeChoiceValue(node, value)
    local values = node.values
    if type(values) ~= "table" or #values == 0 then
        return value ~= nil and value or node.default
    end

    if value ~= nil then
        for _, candidate in ipairs(values) do
            if candidate == value then
                return candidate
            end
        end
    end

    if node.default ~= nil then
        for _, candidate in ipairs(values) do
            if candidate == node.default then
                return candidate
            end
        end
    end

    return values[1]
end

ui.NormalizeChoiceValue = NormalizeChoiceValue

local function NormalizeColor(value)
    if type(value) ~= "table" then
        return nil
    end
    local r = tonumber(value[1])
    local g = tonumber(value[2])
    local b = tonumber(value[3])
    local a = value[4] ~= nil and tonumber(value[4]) or 1
    if r == nil or g == nil or b == nil or a == nil then
        return nil
    end
    return { r, g, b, a }
end

ui.NormalizeColor = NormalizeColor

local function GetCursorPosXSafe(imgui)
    return imgui.GetCursorPosX() or 0
end

ui.GetCursorPosXSafe = GetCursorPosXSafe

local function GetCursorPosYSafe(imgui)
    local value = imgui.GetCursorPosY()
    if type(value) == "number" then
        return value
    end
    return 0
end

ui.GetCursorPosYSafe = GetCursorPosYSafe

local function SetCursorPosSafe(imgui, x, y)
    if type(imgui.SetCursorPos) == "function" then
        imgui.SetCursorPos(x, y)
    end
    if type(imgui.SetCursorPosX) == "function" and type(x) == "number" then
        imgui.SetCursorPosX(x)
    end
    if type(imgui.SetCursorPosY) == "function" and type(y) == "number" then
        imgui.SetCursorPosY(y)
    end
end

ui.SetCursorPosSafe = SetCursorPosSafe

local function GetStyleMetricX(style, key, fallback)
    local metric = style and style[key]
    if type(metric) == "table" and type(metric.x) == "number" then
        return metric.x
    end
    return fallback
end

ui.GetStyleMetricX = GetStyleMetricX

local function GetStyleMetricY(style, key, fallback)
    local metric = style and style[key]
    if type(metric) == "table" and type(metric.y) == "number" then
        return metric.y
    end
    return fallback
end

ui.GetStyleMetricY = GetStyleMetricY

local function CalcTextWidth(imgui, text)
    local width = imgui.CalcTextSize(tostring(text or ""))
    if type(width) == "number" then
        return width
    end
    if type(width) == "table" then
        if type(width.x) == "number" then
            return width.x
        end
        if type(width[1]) == "number" then
            return width[1]
        end
    end
    return 0
end

ui.CalcTextWidth = CalcTextWidth

local function EstimateStructuredRowAdvanceY(imgui)
    local value = imgui.GetFrameHeightWithSpacing()
    if type(value) == "number" and value > 0 then
        return value
    end
    value = imgui.GetTextLineHeightWithSpacing()
    if type(value) == "number" and value > 0 then
        return value
    end
    local style = imgui.GetStyle()
    local framePaddingY = type(style) == "table" and GetStyleMetricY(style, "FramePadding", 3) or 3
    local itemSpacingY = type(style) == "table" and GetStyleMetricY(style, "ItemSpacing", 4) or 4
    return 16 + framePaddingY * 2 + itemSpacingY
end

ui.EstimateStructuredRowAdvanceY = EstimateStructuredRowAdvanceY
widgetHelpers.estimateRowAdvanceY = EstimateStructuredRowAdvanceY

local function DrawStructuredAt(imgui, startX, startY, fallbackHeight, drawFn)
    SetCursorPosSafe(imgui, startX, startY)
    local changed = drawFn() == true
    local endX = GetCursorPosXSafe(imgui)
    local endY = GetCursorPosYSafe(imgui)
    local consumedHeight = endY - startY
    if type(consumedHeight) ~= "number" or consumedHeight <= 0 then
        consumedHeight = fallbackHeight
    end
    return changed, endX, endY, consumedHeight
end

ui.DrawStructuredAt = DrawStructuredAt
widgetHelpers.drawStructuredAt = DrawStructuredAt

local function ShowPreparedTooltip(imgui, node)
    if node and node._hasTooltip == true and imgui.IsItemHovered() then
        imgui.SetTooltip(node._tooltipText)
    end
end

ui.ShowPreparedTooltip = ShowPreparedTooltip

local function EstimateButtonWidth(imgui, label)
    local style = imgui.GetStyle()
    local framePaddingX = GetStyleMetricX(style, "FramePadding", 0)
    return CalcTextWidth(imgui, label) + framePaddingX * 2
end

ui.EstimateButtonWidth = EstimateButtonWidth

function ui.BuildBoundEntries(node, bindOwnerType, uiState)
    local bound = { _changed = false }
    for bindName in pairs(bindOwnerType.binds) do
        local alias = node.binds and node.binds[bindName]
        if alias then
            local a = alias
            local aliasNode = uiState.getAliasNode and uiState.getAliasNode(a) or nil
            local bindEntry = {
                get = function(_) return uiState.get(a) end,
                set = function(_, val) uiState.set(a, val); bound._changed = true end,
                node = aliasNode,
            }
            if aliasNode and aliasNode.type == "packedInt" and aliasNode._bitAliases then
                local children = {}
                for _, child in ipairs(aliasNode._bitAliases) do
                    local childAlias = child.alias
                    local childLabel = child.label or childAlias
                    children[#children + 1] = {
                        alias = childAlias,
                        label = childLabel,
                        get = function() return uiState.get(childAlias) end,
                        set = function(val)
                            uiState.set(childAlias, val)
                            bound._changed = true
                        end,
                    }
                end
                bindEntry.children = children
            end
            bound[bindName] = bindEntry
        end
    end
    node._boundCache = bound
    node._boundCacheUiState = uiState
    node._boundCacheBindOwnerType = bindOwnerType
    return bound
end

local function AssertUiBind(prefix, node, storageNodes, bindName, bindSpec)
    local alias = node.binds and node.binds[bindName]
    local optional = type(bindSpec) == "table" and bindSpec.optional == true
    if type(alias) ~= "string" or alias == "" then
        if not optional then
            libWarn("%s: missing binds.%s", prefix, bindName)
        end
        return
    end
    local storageNode = storageNodes and storageNodes[alias] or nil
    if not storageNode then
        libWarn("%s: binds.%s unknown alias '%s'", prefix, bindName, tostring(alias))
        return
    end
    local expectedKind = type(bindSpec) == "table" and bindSpec.storageType or bindSpec
    if expectedKind ~= nil then
        local expectedKinds = type(expectedKind) == "table" and expectedKind or { expectedKind }
        local matchedKind = false
        for _, kind in ipairs(expectedKinds) do
            if storageNode._valueKind == kind then
                matchedKind = true
                break
            end
        end
        if not matchedKind then
            libWarn("%s: bound alias '%s' is %s, expected %s (binds.%s)",
                prefix,
                tostring(alias),
                tostring(storageNode._valueKind),
                table.concat(expectedKinds, " or "),
                bindName)
        end
    end
    local expectedRootType = type(bindSpec) == "table" and bindSpec.rootType or nil
    if expectedRootType ~= nil and storageNode.type ~= expectedRootType then
        libWarn("%s: bound alias '%s' is root type %s, expected %s (binds.%s)",
            prefix,
            tostring(alias),
            tostring(storageNode.type),
            tostring(expectedRootType),
            bindName)
    end
end

local function ValidateVisibleIf(prefix, node, storageNodes)
    if node.visibleIf == nil then
        return
    end
    if type(node.visibleIf) == "string" then
        if node.visibleIf == "" then
            libWarn("%s: visibleIf must not be empty", prefix)
            return
        end
        local visibleStorage = storageNodes and storageNodes[node.visibleIf] or nil
        if not visibleStorage then
            libWarn("%s: visibleIf alias '%s' does not exist", prefix, tostring(node.visibleIf))
        elseif visibleStorage._valueKind ~= "bool" then
            libWarn("%s: visibleIf alias '%s' must resolve to bool storage", prefix, tostring(node.visibleIf))
        end
        return
    end
    if type(node.visibleIf) ~= "table" then
        libWarn("%s: visibleIf must be a storage alias string or table", prefix)
        return
    end
    local alias = node.visibleIf.alias
    if type(alias) ~= "string" or alias == "" then
        libWarn("%s: visibleIf.alias must be a non-empty string", prefix)
        return
    end
    local visibleStorage = storageNodes and storageNodes[alias] or nil
    if not visibleStorage then
        libWarn("%s: visibleIf alias '%s' does not exist", prefix, tostring(alias))
        return
    end
    local hasValue = node.visibleIf.value ~= nil
    local hasAnyOf = node.visibleIf.anyOf ~= nil
    if hasValue and hasAnyOf then
        libWarn("%s: visibleIf cannot specify both value and anyOf", prefix)
        return
    end
    if not hasValue and not hasAnyOf then
        if visibleStorage._valueKind ~= "bool" then
            libWarn("%s: visibleIf alias '%s' must resolve to bool storage", prefix, tostring(alias))
        end
        return
    end
    if hasAnyOf and (type(node.visibleIf.anyOf) ~= "table" or #node.visibleIf.anyOf == 0) then
        libWarn("%s: visibleIf.anyOf must be a non-empty list", prefix)
    end
end

function ui.DeriveQuickUiNodeId(node)
    if type(node) ~= "table" then
        return nil
    end
    if type(node.quickId) == "string" and node.quickId ~= "" then
        return node.quickId
    end
    if type(node.binds) ~= "table" then
        return nil
    end
    local parts = {}
    for bindName, alias in pairs(node.binds) do
        if type(alias) == "string" and alias ~= "" then
            table.insert(parts, tostring(bindName) .. "=" .. alias)
        end
    end
    if #parts == 0 then
        return nil
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local nextAnonymousImguiId = 0

function ui.EnsureNodeImguiId(node, prefix, widgetType)
    if type(node) ~= "table" then
        return
    end
    if type(node._imguiId) == "string" and node._imguiId ~= "" then
        return
    end
    local idParts = {}
    local binds = type(widgetType) == "table" and type(widgetType.binds) == "table" and widgetType.binds or nil
    if binds ~= nil then
        for bindName in pairs(binds) do
            local alias = type(node.binds) == "table" and node.binds[bindName] or nil
            if type(alias) == "string" and alias ~= "" then
                table.insert(idParts, tostring(bindName) .. "=" .. alias)
            end
        end
    end
    if #idParts > 0 then
        table.sort(idParts)
        node._imguiId = "##" .. table.concat(idParts, "__")
        return
    end
    nextAnonymousImguiId = nextAnonymousImguiId + 1
    node._imguiId = string.format("##anon_%d_%s", nextAnonymousImguiId, tostring(prefix or node.type or "node"))
end

function ui.ValidateUiNode(node, prefix, storageNodes, widgetTypes, layoutTypes)
    widgetTypes = widgetTypes or WidgetTypes
    layoutTypes = layoutTypes or LayoutTypes
    if type(node) ~= "table" then
        libWarn("%s: ui node is not a table", prefix)
        return
    end
    if not node.type then
        libWarn("%s: missing type", prefix)
        return
    end

    local widgetType = widgetTypes[node.type]
    local layoutType = layoutTypes[node.type]
    if widgetType and layoutType then
        libWarn("%s: node type '%s' is both widget and layout", prefix, tostring(node.type))
        return
    end
    if not widgetType and not layoutType then
        libWarn("%s: unknown ui node type '%s'", prefix, tostring(node.type))
        return
    end

    if widgetType then
        node._widgetType = widgetType
        node._layoutType = nil
        widgetType.validate(node, prefix)
        if node.quickId ~= nil and (type(node.quickId) ~= "string" or node.quickId == "") then
            libWarn("%s: quickId must be a non-empty string", prefix)
        end
        for bindName, bindSpec in pairs(widgetType.binds) do
            AssertUiBind(prefix, node, storageNodes, bindName, bindSpec)
        end
        ui.EnsureNodeImguiId(node, prefix, widgetType)
        node._quickId = ui.DeriveQuickUiNodeId(node)
    else
        node._layoutType = layoutType
        node._widgetType = nil
        layoutType.validate(node, prefix)
        if type(layoutType.binds) == "table" then
            for bindName, bindSpec in pairs(layoutType.binds) do
                AssertUiBind(prefix, node, storageNodes, bindName, bindSpec)
            end
        end
        if node.children ~= nil then
            if type(node.children) ~= "table" then
                libWarn("%s: children must be a table", prefix)
            else
                for childIndex, child in ipairs(node.children) do
                    ui.ValidateUiNode(child, prefix .. " child #" .. childIndex, storageNodes, widgetTypes, layoutTypes)
                end
            end
        end
    end

    ValidateVisibleIf(prefix, node, storageNodes)
end
