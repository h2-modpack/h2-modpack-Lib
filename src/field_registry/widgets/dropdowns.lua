local internal = AdamantModpackLib_Internal
local WidgetTypes = public.registry.widgets
local libWarn = internal.logging.warnIf
local ui = internal.ui
local widgets = internal.widgets

local NormalizeChoiceValue = ui.NormalizeChoiceValue
local PrepareWidgetText = widgets.PrepareWidgetText
local ChoiceDisplay = widgets.ChoiceDisplay
local GetStyleMetricX = ui.GetStyleMetricX
local CalcTextWidth = ui.CalcTextWidth
local EstimateButtonWidth = ui.EstimateButtonWidth
local EstimateStructuredRowAdvanceY = ui.EstimateStructuredRowAdvanceY
local DrawStructuredAt = ui.DrawStructuredAt
local ShowPreparedTooltip = ui.ShowPreparedTooltip

local choiceHelpers = widgets.choiceHelpers
local ValidateValueColorsTable = choiceHelpers.ValidateValueColorsTable
local DrawWithValueColor = choiceHelpers.DrawWithValueColor
local MakeSelectableId = choiceHelpers.MakeSelectableId
local GetPackedChoiceChildren = choiceHelpers.GetPackedChoiceChildren
local GetPackedChoiceLabel = choiceHelpers.GetPackedChoiceLabel
local ClassifyPackedChoice = choiceHelpers.ClassifyPackedChoice
local ApplyPackedChoiceSelection = choiceHelpers.ApplyPackedChoiceSelection
local ClearPackedChoiceSelection = choiceHelpers.ClearPackedChoiceSelection
local ValidatePackedChoiceWidget = choiceHelpers.ValidatePackedChoiceWidget

local function PrepareStaticDropdownOptions(node)
    local options = {}
    for index, candidate in ipairs(node.values or {}) do
        options[#options + 1] = {
            value = candidate,
            label = ChoiceDisplay(node, candidate),
            color = node._valueColors and node._valueColors[candidate] or nil,
            uniqueId = index,
        }
    end
    return options
end

local function PrepareStaticPackedDropdownOptions(node)
    local bindNodes = node._bindNodes
    local aliasNode = bindNodes and bindNodes.value or nil
    local children = aliasNode and aliasNode._bitAliases or nil
    if type(children) ~= "table" then
        return nil
    end

    local options = {
        {
            alias = nil,
            label = node.noneLabel or "None",
            color = nil,
            uniqueId = "none",
            isNone = true,
        },
    }
    for _, child in ipairs(children) do
        options[#options + 1] = {
            alias = child.alias,
            label = GetPackedChoiceLabel(node, child),
            color = node._valueColors and node._valueColors[child.alias] or nil,
            uniqueId = child.alias,
            isNone = false,
        }
    end
    return options
end

local function DrawLabeledDropdownControl(imgui, node, x, y, availWidth, estimatedControlWidth, drawControl)
    local labelText = node._label or ""
    local hasLabel = node._hasLabel == true
    local labelWidth = hasLabel and CalcTextWidth(imgui, labelText) or 0
    local controlWidth = type(node.controlWidth) == "number" and node.controlWidth > 0
        and node.controlWidth
        or availWidth or estimatedControlWidth
    local controlGap = type(node.controlGap) == "number"
        and node.controlGap >= 0
        and node.controlGap
        or GetStyleMetricX(imgui.GetStyle(), "ItemSpacing", 8)

    local controlSlotX
    if hasLabel then
        controlSlotX = x + labelWidth + controlGap
    else
        controlSlotX = x
    end

    local maxHeight = 0
    local changed = false

    if hasLabel then
        local _, _, _, labelHeight = DrawStructuredAt(
            imgui,
            x,
            y,
            EstimateStructuredRowAdvanceY(imgui),
            function()
                imgui.AlignTextToFramePadding()
                imgui.Text(labelText)
                ShowPreparedTooltip(imgui, node)
                return false
            end)
        if type(labelHeight) == "number" and labelHeight > maxHeight then
            maxHeight = labelHeight
        end
    end

    local controlChanged, _, _, controlHeight = DrawStructuredAt(
        imgui,
        controlSlotX,
        y,
        EstimateStructuredRowAdvanceY(imgui),
        function()
            if type(controlWidth) == "number" and controlWidth > 0 then
                imgui.PushItemWidth(controlWidth)
            end
            local widgetChanged = drawControl(controlWidth)
            if type(controlWidth) == "number" and controlWidth > 0 then
                imgui.PopItemWidth()
            end
            ShowPreparedTooltip(imgui, node)
            return widgetChanged == true
        end)
    if controlChanged then
        changed = true
    end
    if type(controlHeight) == "number" and controlHeight > maxHeight then
        maxHeight = controlHeight
    end

    local consumedWidth = math.max((controlSlotX - x) + controlWidth, hasLabel and labelWidth or 0)
    return consumedWidth, maxHeight, changed
end

WidgetTypes.dropdown = {
    binds = { value = { storageType = { "string", "int" } } },
    params = {
        label = { type = "string", optional = true },
        tooltip = { type = "string", optional = true },
        values = { type = "table", required = true },
        displayValues = { type = "table", optional = true },
        valueColors = { type = "table", optional = true },
        controlWidth = { type = "number", optional = true },
        controlGap = { type = "number", optional = true },
        quick = { type = "boolean", optional = true },
    },
    validate = function(node, prefix)
        if not node.values then
            libWarn("%s: dropdown missing values list", prefix)
        elseif type(node.values) ~= "table" or #node.values == 0 then
            libWarn("%s: dropdown values must be a non-empty list", prefix)
        else
            for _, value in ipairs(node.values) do
                if type(value) == "string" and string.find(value, "|", 1, true) then
                    libWarn("%s: value '%s' contains reserved separator '|'", prefix, value)
                elseif type(value) ~= "string" and (type(value) ~= "number" or value ~= math.floor(value)) then
                    libWarn("%s: dropdown values must contain only strings or integers", prefix)
                end
            end
        end
        if node.displayValues ~= nil and type(node.displayValues) ~= "table" then
            libWarn("%s: dropdown displayValues must be a table", prefix)
        end
        if node.controlGap ~= nil and (type(node.controlGap) ~= "number" or node.controlGap < 0) then
            libWarn("%s: dropdown controlGap must be a non-negative number", prefix)
        end
        ValidateValueColorsTable(node, prefix, "dropdown")
        PrepareWidgetText(node, node.binds and node.binds.value)
        node._hasLabel = (node._label or "") ~= ""
        node._options = PrepareStaticDropdownOptions(node)
    end,
    draw = function(imgui, node, bound, x, y, availWidth)
        local current = NormalizeChoiceValue(node, bound.value:get())
        local currentOption = nil
        for _, option in ipairs(node._options or {}) do
            if option.value == current then
                currentOption = option
                break
            end
        end
        currentOption = currentOption or (node._options and node._options[1]) or nil
        local previewValue = currentOption and currentOption.value or ""
        local previewText = currentOption and currentOption.label or ChoiceDisplay(node, previewValue)
        local previewColor = currentOption and currentOption.color or nil
        local estimatedControlWidth = EstimateButtonWidth(imgui, previewText) + 16

        return DrawLabeledDropdownControl(
            imgui,
            node,
            x,
            y,
            availWidth,
            estimatedControlWidth,
            function()
                local opened = DrawWithValueColor(imgui, previewColor, function()
                    return imgui.BeginCombo(node._imguiId, previewText)
                end)
                if not opened then
                    return false
                end

                local changed = false
                local pendingValue = nil
                for _, option in ipairs(node._options or {}) do
                    local selected = DrawWithValueColor(imgui, option.color, function()
                        return imgui.Selectable(
                            MakeSelectableId(option.label, option.uniqueId),
                            false)
                    end)
                    if selected and option.value ~= current then
                        pendingValue = option.value
                    end
                end
                imgui.EndCombo()
                if pendingValue ~= nil then
                    bound.value:set(pendingValue)
                    changed = true
                end
                return changed
            end)
    end,
}

WidgetTypes.mappedDropdown = {
    binds = { value = {} },
    params = {
        label = { type = "string", optional = true },
        tooltip = { type = "string", optional = true },
        getPreview = { type = "function", required = true },
        getOptions = { type = "function", required = true },
        getPreviewColor = { type = "function", optional = true },
        controlWidth = { type = "number", optional = true },
        controlGap = { type = "number", optional = true },
        quick = { type = "boolean", optional = true },
    },
    validate = function(node, prefix)
        if type(node.getPreview) ~= "function" then
            libWarn("%s: mappedDropdown getPreview must be function", prefix)
        end
        if type(node.getOptions) ~= "function" then
            libWarn("%s: mappedDropdown getOptions must be function", prefix)
        end
        if node.getPreviewColor ~= nil and type(node.getPreviewColor) ~= "function" then
            libWarn("%s: mappedDropdown getPreviewColor must be function", prefix)
        end
        if node.controlGap ~= nil and (type(node.controlGap) ~= "number" or node.controlGap < 0) then
            libWarn("%s: mappedDropdown controlGap must be a non-negative number", prefix)
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
        node._hasLabel = (node._label or "") ~= ""
    end,
    draw = function(imgui, node, bound, x, y, availWidth, _, uiState)
        local ctx = node._mappedDropdownCtx or {}
        ctx.boundValue = bound.value
        ctx.current = bound.value and bound.value.get and bound.value:get() or nil
        ctx.uiState = uiState
        ctx.preview = type(node.getPreview) == "function"
            and tostring(node.getPreview(node, bound, uiState) or "")
            or ""
        ctx.previewColor = type(node.getPreviewColor) == "function"
            and node.getPreviewColor(node, bound, uiState)
            or nil
        ctx.options = type(node.getOptions) == "function"
            and node.getOptions(node, bound, uiState)
            or {}
        node._mappedDropdownCtx = ctx
        local estimatedControlWidth = EstimateButtonWidth(imgui, ctx.preview or "") + 16
        return DrawLabeledDropdownControl(
            imgui,
            node,
            x,
            y,
            availWidth,
            estimatedControlWidth,
            function()
                local opened = DrawWithValueColor(imgui, ctx.previewColor, function()
                    return imgui.BeginCombo(node._imguiId, ctx.preview or "")
                end)
                if not opened then
                    return false
                end

                local changed = false
                for _, option in ipairs(ctx.options or {}) do
                    local label
                    if type(option) == "table" then
                        label = tostring(option.label or option.value or "")
                    else
                        label = tostring(option or "")
                    end

                    local optionColor = type(option) == "table" and option.color or nil
                    local clicked = DrawWithValueColor(imgui, optionColor, function()
                        local uniqueId = type(option) == "table"
                            and (option.id or option.value or label)
                            or option
                        return imgui.Selectable(MakeSelectableId(label, uniqueId), false)
                    end)
                    if clicked then
                        if type(option) == "table" and type(option.onSelect) == "function" then
                            changed = option.onSelect(option, ctx.boundValue, ctx.uiState, node) == true or changed
                        else
                            local nextValue = type(option) == "table" and option.value or option
                            if nextValue ~= ctx.current then
                                ctx.boundValue:set(nextValue)
                                changed = true
                            end
                        end
                    end
                end

                imgui.EndCombo()
                return changed
            end)
    end,
}

WidgetTypes.packedDropdown = {
    binds = { value = { storageType = "int", rootType = "packedInt" } },
    params = {
        label = { type = "string", optional = true },
        tooltip = { type = "string", optional = true },
        noneLabel = { type = "string", optional = true },
        multipleLabel = { type = "string", optional = true },
        packedDisplayValues = { type = "table", optional = true },
        valueColors = { type = "table", optional = true },
        controlWidth = { type = "number", optional = true },
        controlGap = { type = "number", optional = true },
        quick = { type = "boolean", optional = true },
    },
    validate = function(node, prefix)
        PrepareWidgetText(node, node.binds and node.binds.value)
        ValidatePackedChoiceWidget(node, prefix, "packedDropdown")
        if node.controlGap ~= nil and (type(node.controlGap) ~= "number" or node.controlGap < 0) then
            libWarn("%s: packedDropdown controlGap must be a non-negative number", prefix)
        end
        node._hasLabel = (node._label or "") ~= ""
        node._options = PrepareStaticPackedDropdownOptions(node)
    end,
    draw = function(imgui, node, bound, x, y, availWidth)
        local children = GetPackedChoiceChildren(node, bound, "packedDropdown")
        if not children then
            return 0, 0, false
        end

        local selection = ClassifyPackedChoice(node, children)
        local noneLabel = node.noneLabel or "None"
        local multipleLabel = node.multipleLabel or "Multiple"
        local preview
        local previewColor = nil
        if selection.state == "single" and selection.selectedChild then
            preview = GetPackedChoiceLabel(node, selection.selectedChild)
            previewColor = node._valueColors and node._valueColors[selection.selectedChild.alias] or nil
        elseif selection.state == "multiple" then
            preview = multipleLabel
        else
            preview = noneLabel
        end
        local estimatedControlWidth = EstimateButtonWidth(imgui, preview or "") + 16
        return DrawLabeledDropdownControl(
            imgui,
            node,
            x,
            y,
            availWidth,
            estimatedControlWidth,
            function()
                local opened = DrawWithValueColor(imgui, previewColor, function()
                    return imgui.BeginCombo(node._imguiId, preview or "")
                end)
                if not opened then
                    return false
                end

                local changed = false
                local pendingClear = false
                local pendingAlias = nil
                for _, option in ipairs(node._options or {}) do
                    local clicked = DrawWithValueColor(imgui, option.color, function()
                        return imgui.Selectable(MakeSelectableId(option.label, option.uniqueId), false)
                    end)
                    if clicked then
                        if option.isNone then
                            pendingClear = true
                            pendingAlias = nil
                        else
                            pendingClear = false
                            pendingAlias = option.alias
                        end
                    end
                end

                imgui.EndCombo()
                if pendingAlias ~= nil then
                    changed = ApplyPackedChoiceSelection(children, pendingAlias, selection) or changed
                elseif pendingClear then
                    changed = ClearPackedChoiceSelection(children, selection) or changed
                end
                return changed
            end)
    end,
}
