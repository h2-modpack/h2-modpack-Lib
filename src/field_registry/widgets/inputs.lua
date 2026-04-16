local internal = AdamantModpackLib_Internal
local WidgetTypes = public.registry.widgets
local libWarn = internal.logging.warnIf
local ui = internal.ui
local widgets = internal.widgets

local PrepareWidgetText = widgets.PrepareWidgetText
local GetStyleMetricX = ui.GetStyleMetricX
local CalcTextWidth = ui.CalcTextWidth
local EstimateStructuredRowAdvanceY = ui.EstimateStructuredRowAdvanceY
local DrawStructuredAt = ui.DrawStructuredAt
local ShowPreparedTooltip = ui.ShowPreparedTooltip

WidgetTypes.inputText = {
    binds = { value = { storageType = "string" } },
    params = {
        label = { type = "string", optional = true },
        tooltip = { type = "string", optional = true },
        maxLen = { type = "number", optional = true },
        controlWidth = { type = "number", optional = true },
        controlGap = { type = "number", optional = true },
        quick = { type = "boolean", optional = true },
    },
    validate = function(node, prefix)
        if node.maxLen ~= nil and (type(node.maxLen) ~= "number" or node.maxLen < 1) then
            libWarn("%s: inputText maxLen must be a positive number", prefix)
        end
        if node.controlWidth ~= nil and (type(node.controlWidth) ~= "number" or node.controlWidth <= 0) then
            libWarn("%s: inputText controlWidth must be a positive number", prefix)
        end
        if node.controlGap ~= nil and (type(node.controlGap) ~= "number" or node.controlGap < 0) then
            libWarn("%s: inputText controlGap must be a non-negative number", prefix)
        end
        node._maxLen = math.floor(tonumber(node.maxLen) or 0)
        if node._maxLen < 1 then
            node._maxLen = nil
        end
        PrepareWidgetText(node, node.binds and node.binds.value)
        node._hasLabel = (node._label or "") ~= ""
    end,
    draw = function(imgui, node, bound, x, y, availWidth)
        local aliasNode = bound.value and bound.value.node or nil
        local boundValue = bound.value
        local current = tostring(boundValue:get() or "")
        local maxLen = node._maxLen or (aliasNode and aliasNode._maxLen) or 256
        local labelText = node._label or ""
        local hasLabel = node._hasLabel == true
        local labelWidth = hasLabel and CalcTextWidth(imgui, labelText) or 0
        local controlWidth = type(node.controlWidth) == "number" and node.controlWidth > 0
            and node.controlWidth
            or availWidth or 120
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
                local newValue, widgetChanged = imgui.InputText(node._imguiId, current, maxLen)
                if type(controlWidth) == "number" and controlWidth > 0 then
                    imgui.PopItemWidth()
                end
                ShowPreparedTooltip(imgui, node)
                if widgetChanged then
                    boundValue:set(newValue)
                    return true
                end
                return false
            end)
        if controlChanged then
            changed = true
        end
        if type(controlHeight) == "number" and controlHeight > maxHeight then
            maxHeight = controlHeight
        end

        local consumedWidth = math.max((controlSlotX - x) + controlWidth, hasLabel and labelWidth or 0)
        return consumedWidth, maxHeight, changed
    end,
}
