local internal = AdamantModpackLib_Internal
local widgets = internal.widgets

local function PrepareWidgetText(node, fallbackLabel)
    if type(node) ~= "table" then
        return
    end
    node._label = tostring(node.label or fallbackLabel or "")
    node._tooltipText = node.tooltip ~= nil and tostring(node.tooltip) or ""
    node._hasTooltip = node._tooltipText ~= ""
end

widgets.PrepareWidgetText = PrepareWidgetText

local function ChoiceDisplay(node, value)
    if node.displayValues and node.displayValues[value] ~= nil then
        return tostring(node.displayValues[value])
    end
    return tostring(value)
end

widgets.ChoiceDisplay = ChoiceDisplay
