local internal = AdamantModpackLib_Internal
local WidgetTypes = public.registry.widgets
local libWarn = internal.logging.warnIf
local ui = internal.ui
local widgets = internal.widgets

local NormalizeChoiceValue = ui.NormalizeChoiceValue
local PrepareWidgetText = widgets.PrepareWidgetText
local ChoiceDisplay = widgets.ChoiceDisplay
local CalcTextWidth = ui.CalcTextWidth
local GetStyleMetricX = ui.GetStyleMetricX
local EstimateStructuredRowAdvanceY = ui.EstimateStructuredRowAdvanceY
local ShowPreparedTooltip = ui.ShowPreparedTooltip
local EstimateToggleWidth = ui.EstimateToggleWidth
local DrawOrderedEntries = ui.DrawOrderedEntries

local choiceHelpers = widgets.choiceHelpers
local ValidateValueColorsTable = choiceHelpers.ValidateValueColorsTable
local DrawWithValueColor = choiceHelpers.DrawWithValueColor
local GetPackedChoiceChildren = choiceHelpers.GetPackedChoiceChildren
local GetPackedChoiceLabel = choiceHelpers.GetPackedChoiceLabel
local ClassifyPackedChoice = choiceHelpers.ClassifyPackedChoice
local ApplyPackedChoiceSelection = choiceHelpers.ApplyPackedChoiceSelection
local ClearPackedChoiceSelection = choiceHelpers.ClearPackedChoiceSelection
local ValidatePackedChoiceWidget = choiceHelpers.ValidatePackedChoiceWidget

local function CompareEntries(left, right)
    if left.line ~= right.line then
        return left.line < right.line
    end
    if type(left.start) == "number" and type(right.start) == "number" and left.start ~= right.start then
        return left.start < right.start
    end
    return left.index < right.index
end

local function BuildOrderedChoiceEntries(node, options)
    options = options or {}
    local labelText = options.labelText
    if labelText == nil then
        labelText = node._label or ""
    end
    local labelSlotName = options.labelSlotName or "label"
    local entries = {}

    local function OptionGap(imgui)
        if type(options.optionGap) == "number" and options.optionGap >= 0 then
            return options.optionGap
        end
        local style = type(imgui.GetStyle) == "function" and imgui.GetStyle() or nil
        return GetStyleMetricX(style, "ItemSpacing", 8)
    end

    local function AddEntry(name, config)
        entries[#entries + 1] = {
            index = #entries + 1,
            name = name,
            line = config.line or 1,
            start = config.start,
            width = config.width,
            align = config.align,
            estimateWidth = config.estimateWidth,
            render = config.render,
        }
    end

    if labelText ~= "" then
        AddEntry(labelSlotName, {
            estimateWidth = function(imgui)
                return CalcTextWidth(imgui, labelText)
            end,
            render = function(imgui)
                imgui.Text(labelText)
                ShowPreparedTooltip(imgui, node)
                return false, CalcTextWidth(imgui, labelText), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
    end

    for index, option in ipairs(options.optionEntries or {}) do
        local slotName = option.slotName or ("option:" .. tostring(index))
        AddEntry(slotName, {
            line = option.line,
            start = option.start,
            width = option.width,
            align = option.align,
            estimateWidth = function(imgui)
                return EstimateToggleWidth(imgui, option.label)
            end,
            render = function(imgui)
                local clicked = DrawWithValueColor(imgui, option.color, function()
                    return imgui.RadioButton(option.label, option.selected == true)
                end)
                if clicked and type(option.onSelect) == "function" then
                    return option.onSelect() == true, EstimateToggleWidth(imgui, option.label), EstimateStructuredRowAdvanceY(imgui)
                end
                return false, EstimateToggleWidth(imgui, option.label), EstimateStructuredRowAdvanceY(imgui)
            end,
        })
        if index < #(options.optionEntries or {}) then
            AddEntry(slotName .. ":gap", {
                line = option.line,
                estimateWidth = function(imgui)
                    return OptionGap(imgui)
                end,
                render = function(imgui)
                    return false, OptionGap(imgui), EstimateStructuredRowAdvanceY(imgui)
                end,
            })
        end
    end

    table.sort(entries, CompareEntries)

    return entries
end

local function PrepareStaticRadioOptionEntries(node)
    local optionEntries = {}
    for index, candidate in ipairs(node.values or {}) do
        optionEntries[#optionEntries + 1] = {
            slotName = "option:" .. tostring(index),
            value = candidate,
            label = ChoiceDisplay(node, candidate),
            color = node._valueColors and node._valueColors[candidate] or nil,
        }
    end
    return optionEntries
end

local function PrepareStaticPackedRadioOptionEntries(node)
    local bindNodes = node._bindNodes
    local aliasNode = bindNodes and bindNodes.value or nil
    local children = aliasNode and aliasNode._bitAliases or nil
    if type(children) ~= "table" then
        return nil
    end

    local optionEntries = {
        {
            slotName = "option:none",
            alias = nil,
            label = node.noneLabel or "None",
            color = nil,
            isNone = true,
        },
    }
    for index, child in ipairs(children) do
        optionEntries[#optionEntries + 1] = {
            slotName = "option:" .. tostring(index),
            alias = child.alias,
            label = GetPackedChoiceLabel(node, child),
            color = node._valueColors and node._valueColors[child.alias] or nil,
            isNone = false,
        }
    end
    return optionEntries
end

WidgetTypes.radio = {
    binds = { value = { storageType = { "string", "int" } } },
    params = {
        label = { type = "string", optional = true },
        tooltip = { type = "string", optional = true },
        values = { type = "table", required = true },
        displayValues = { type = "table", optional = true },
        valueColors = { type = "table", optional = true },
        optionGap = { type = "number", optional = true },
        quick = { type = "boolean", optional = true },
    },
    validate = function(node, prefix)
        if not node.values then
            libWarn("%s: radio missing values list", prefix)
        elseif type(node.values) ~= "table" or #node.values == 0 then
            libWarn("%s: radio values must be a non-empty list", prefix)
        else
            for _, value in ipairs(node.values) do
                if type(value) == "string" and string.find(value, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, value)
                elseif type(value) ~= "string" and (type(value) ~= "number" or value ~= math.floor(value)) then
                    libWarn("%s: radio values must contain only strings or integers", prefix)
                end
            end
        end
        if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
            libWarn("%s: radio displayValues must be a table", prefix)
        end
        if node.optionGap ~= nil and (type(node.optionGap) ~= "number" or node.optionGap < 0) then
            libWarn("%s: radio optionGap must be a non-negative number", prefix)
        end
        ValidateValueColorsTable(node, prefix, "radio")
        PrepareWidgetText(node, node.binds and node.binds.value)
        node._optionEntries = PrepareStaticRadioOptionEntries(node)
    end,
    draw = function(imgui, node, bound, x, y)
        local ctx = node._radioCtx or {}
        ctx.boundValue = bound.value
        ctx.current = NormalizeChoiceValue(node, bound.value:get())
        node._radioCtx = ctx
        local optionEntries = {}
        for index, option in ipairs(node._optionEntries or {}) do
            local candidate = option.value
            optionEntries[#optionEntries + 1] = {
                slotName = option.slotName or ("option:" .. tostring(index)),
                label = option.label,
                color = option.color,
                selected = ctx.current == candidate,
                onSelect = function()
                    if candidate ~= ctx.current then
                        ctx.boundValue:set(candidate)
                        ctx.current = candidate
                        return true
                    end
                    return false
                end,
            }
        end
        return DrawOrderedEntries(
            imgui,
            BuildOrderedChoiceEntries(node, {
                optionEntries = optionEntries,
                optionGap = node.optionGap,
            }),
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui))
    end,
}

WidgetTypes.mappedRadio = {
    binds = { value = {} },
    params = {
        label = { type = "string", optional = true },
        tooltip = { type = "string", optional = true },
        getOptions = { type = "function", required = true },
        optionGap = { type = "number", optional = true },
        quick = { type = "boolean", optional = true },
    },
    validate = function(node, prefix)
        if type(node.getOptions) ~= "function" then
            libWarn("%s: mappedRadio getOptions must be function", prefix)
        end
        if node.optionGap ~= nil and (type(node.optionGap) ~= "number" or node.optionGap < 0) then
            libWarn("%s: mappedRadio optionGap must be a non-negative number", prefix)
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
    end,
    draw = function(imgui, node, bound, x, y, _, _, uiState)
        local ctx = node._mappedRadioCtx or {}
        ctx.boundValue = bound.value
        ctx.current = bound.value and bound.value.get and bound.value:get() or nil
        ctx.uiState = uiState
        ctx.options = type(node.getOptions) == "function"
            and node.getOptions(node, bound, uiState)
            or {}
        node._mappedRadioCtx = ctx

        local optionEntries = {}
        for index, option in ipairs(ctx.options or {}) do
            local label
            local selected
            if type(option) == "table" then
                label = tostring(option.label or option.value or "")
                selected = option.selected == true
            else
                label = tostring(option or "")
                selected = ctx.current ~= nil and option == ctx.current or false
            end
            optionEntries[#optionEntries + 1] = {
                slotName = "option:" .. tostring(index),
                label = label,
                selected = selected,
                onSelect = function()
                    if type(option) == "table" and type(option.onSelect) == "function" then
                        return option.onSelect(option, ctx.boundValue, ctx.uiState, node) == true
                    end

                    local nextValue = type(option) == "table" and option.value or option
                    if nextValue ~= ctx.current then
                        ctx.boundValue:set(nextValue)
                        ctx.current = nextValue
                        return true
                    end
                    return false
                end,
            }
        end

        return DrawOrderedEntries(
            imgui,
            BuildOrderedChoiceEntries(node, {
                optionEntries = optionEntries,
                optionGap = node.optionGap,
            }),
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui))
    end,
}

WidgetTypes.packedRadio = {
    binds = { value = { storageType = "int", rootType = "packedInt" } },
    params = {
        label = { type = "string", optional = true },
        tooltip = { type = "string", optional = true },
        noneLabel = { type = "string", optional = true },
        packedDisplayValues = { type = "table", optional = true },
        valueColors = { type = "table", optional = true },
        optionGap = { type = "number", optional = true },
        quick = { type = "boolean", optional = true },
    },
    validate = function(node, prefix)
        PrepareWidgetText(node, node.binds and node.binds.value)
        ValidatePackedChoiceWidget(node, prefix, "packedRadio")
        if node.optionGap ~= nil and (type(node.optionGap) ~= "number" or node.optionGap < 0) then
            libWarn("%s: packedRadio optionGap must be a non-negative number", prefix)
        end
        node._optionEntries = PrepareStaticPackedRadioOptionEntries(node)
    end,
    draw = function(imgui, node, bound, x, y)
        local children = GetPackedChoiceChildren(node, bound, "packedRadio")
        if not children then
            return 0, 0, false
        end

        local selection = ClassifyPackedChoice(node, children)
        local optionEntries = {}
        for index, option in ipairs(node._optionEntries or {}) do
            optionEntries[#optionEntries + 1] = {
                slotName = option.slotName or ("option:" .. tostring(index)),
                label = option.label,
                color = option.color,
                selected = option.isNone
                    and selection.state == "none"
                    or (selection.selectedChild and selection.selectedChild.alias == option.alias or false),
                onSelect = function()
                    if option.isNone then
                        return ClearPackedChoiceSelection(children, selection) == true
                    end
                    return ApplyPackedChoiceSelection(children, option.alias, selection) == true
                end,
            }
        end

        return DrawOrderedEntries(
            imgui,
            BuildOrderedChoiceEntries(node, {
                optionEntries = optionEntries,
                optionGap = node.optionGap,
            }),
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui))
    end,
}
