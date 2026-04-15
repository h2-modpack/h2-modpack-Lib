local internal = AdamantModpackLib_Internal
local libWarn = internal.logging.warnIf
local registry = internal.registry
local uiInternal = internal.ui
public.ui = public.ui or {}
local ui = public.ui

local ValidateCustomTypes = registry.ValidateCustomTypes
local MergeCustomTypes = registry.MergeCustomTypes
local EnsurePreparedStorage = uiInternal.EnsurePreparedStorage
local DrawLayoutNode = uiInternal.DrawLayoutNode
local GetCursorPosXSafe = uiInternal.GetCursorPosXSafe
local GetCursorPosYSafe = uiInternal.GetCursorPosYSafe
local SetCursorPosSafe = uiInternal.SetCursorPosSafe

--- Validates a UI tree against the current widget, layout, and storage registries.
---@param uiNodes table Ordered list of UI nodes to validate.
---@param label string Validation label used to prefix warnings.
---@param storage table|nil Storage schema used to resolve binds and visibility aliases.
---@param customTypes table|nil Optional custom widget/layout registry extensions.
function ui.validate(uiNodes, label, storage, customTypes)
    if type(uiNodes) ~= "table" then
        libWarn("%s: ui is not a table", label)
        return
    end
    if customTypes ~= nil then
        ValidateCustomTypes(customTypes, label)
    end
    local widgetTypes, layoutTypes = MergeCustomTypes(customTypes)
    local storageNodes = EnsurePreparedStorage(storage, label and (label .. " storage") or "validateUi storage")
    for index, node in ipairs(uiNodes) do
        uiInternal.ValidateUiNode(node, label .. " ui #" .. index, storageNodes, widgetTypes, layoutTypes)
    end
end

--- Validates a single UI node against the current widget, layout, and storage registries.
---@param node table UI node to validate in place.
---@param label string|nil Optional label used to prefix validation warnings.
---@param storage table|nil Storage schema used to resolve binds and visibility aliases.
---@param customTypes table|nil Optional custom widget/layout registry extensions.
function ui.prepareNode(node, label, storage, customTypes)
    local prefix = label or "prepareUiNode"
    local widgetTypes, layoutTypes = MergeCustomTypes(customTypes)
    uiInternal.ValidateUiNode(node, prefix, EnsurePreparedStorage(storage, prefix .. " storage"), widgetTypes, layoutTypes)
end

--- Validates a single widget node without requiring a full UI tree or storage schema.
---@param node table Widget node to validate in place.
---@param label string|nil Optional label used to prefix validation warnings.
---@param customTypes table|nil Optional custom widget registry extensions.
function ui.prepareWidgetNode(node, label, customTypes)
    local prefix = label or "prepareWidgetNode"
    if type(node) ~= "table" then
        libWarn("%s: widget node is not a table", prefix)
        return
    end
    if type(node.type) ~= "string" or node.type == "" then
        libWarn("%s: widget node missing type", prefix)
        return
    end
    local widgetTypes = select(1, MergeCustomTypes(customTypes))
    local widgetType = widgetTypes[node.type]
    if not widgetType then
        libWarn("%s: unknown widget type '%s'", prefix, tostring(node.type))
        return
    end
    widgetType.validate(node, prefix)
    uiInternal.EnsureNodeImguiId(node, prefix, widgetType)
end

--- Validates a list of UI nodes and returns a bind-alias registry for the prepared nodes.
---@param nodes table Ordered list of UI nodes to validate.
---@param label string|nil Optional label used to prefix validation warnings.
---@param storage table|nil Storage schema used to resolve binds and visibility aliases.
---@param customTypes table|nil Optional custom widget/layout registry extensions.
---@return table registryTable Map from bind alias to the prepared UI node that declared it.
function ui.prepareNodes(nodes, label, storage, customTypes)
    local prefix = label or "prepareUiNodes"
    local preparedStorage = EnsurePreparedStorage(storage, prefix .. " storage")
    local widgetTypes, layoutTypes = MergeCustomTypes(customTypes)
    local registryTable = {}
    for _, node in ipairs(nodes) do
        uiInternal.ValidateUiNode(node, prefix, preparedStorage, widgetTypes, layoutTypes)
        for _, alias in pairs(node.binds or {}) do
            registryTable[alias] = node
        end
    end
    return registryTable
end

--- Evaluates whether a UI node should be visible for the supplied view-state snapshot.
---@param node table UI node whose `visibleIf` contract should be evaluated.
---@param view table|nil View-state table keyed by storage alias.
---@return boolean visible True when the node should be rendered for the current view state.
function ui.isVisible(node, view)
    if not node.visibleIf then
        return true
    end
    if type(node.visibleIf) == "string" then
        return view and view[node.visibleIf] == true or false
    end
    if type(node.visibleIf) ~= "table" then
        return false
    end

    local alias = node.visibleIf.alias
    if type(alias) ~= "string" or alias == "" then
        return false
    end

    local value = view and view[alias]
    if node.visibleIf.value ~= nil then
        return value == node.visibleIf.value
    end
    if node.visibleIf.anyOf ~= nil then
        if type(node.visibleIf.anyOf) ~= "table" then
            return false
        end
        for _, expected in ipairs(node.visibleIf.anyOf) do
            if value == expected then
                return true
            end
        end
        return false
    end
    return value == true
end

local function DrawUiNodeAt(imgui, node, uiState, x, y, availWidth, availHeight, widgetTypes, layoutTypes)
    if not ui.isVisible(node, uiState and uiState.view) then
        return 0, 0, false
    end

    local function drawChild(child, childX, childY, childAvailWidth, childAvailHeight)
        return DrawUiNodeAt(
            imgui,
            child,
            uiState,
            type(childX) == "number" and childX or x,
            type(childY) == "number" and childY or y,
            childAvailWidth ~= nil and childAvailWidth or availWidth,
            childAvailHeight ~= nil and childAvailHeight or availHeight,
            widgetTypes,
            layoutTypes)
    end

    local wasLayout, layoutWidth, layoutHeight, layoutChanged = DrawLayoutNode(
        imgui,
        node,
        drawChild,
        layoutTypes,
        uiState,
        x,
        y,
        availWidth,
        availHeight)
    if wasLayout then
        SetCursorPosSafe(imgui, x, y + layoutHeight)
        return layoutWidth, layoutHeight, layoutChanged
    end

    local widgetType = widgetTypes[node.type]
    if not widgetType then
        libWarn("drawUiNode: unknown node type '%s'", tostring(node.type))
        return 0, 0, false
    end

    imgui.PushID(node._imguiId or tostring(node.type))
    local drawX = x
    if node.indent then
        SetCursorPosSafe(imgui, x, y)
        imgui.Indent()
        drawX = GetCursorPosXSafe(imgui)
    end

    local bound = node._boundCache
    if bound == nil or node._boundCacheUiState ~= uiState or node._boundCacheBindOwnerType ~= widgetType then
        bound = uiInternal.BuildBoundEntries(node, widgetType, uiState)
    end
    bound._changed = false

    local drawChanged = false
    local consumedWidth = 0
    local consumedHeight = 0
    if type(widgetType.draw) == "function" then
        local ok, resultWidth, resultHeight, resultChanged = xpcall(function()
            return widgetType.draw(
                imgui,
                node,
                bound,
                drawX,
                y,
                availWidth,
                availHeight,
                uiState)
        end, function(err)
            return debug.traceback(err, 2)
        end)
        if not ok then
            error(resultWidth, 0)
        end
        consumedWidth = type(resultWidth) == "number" and resultWidth or 0
        consumedHeight = type(resultHeight) == "number" and resultHeight or 0
        drawChanged = resultChanged == true
    else
        libWarn("drawUiNode: widget type '%s' is missing draw", tostring(node.type))
    end

    if node.indent then
        imgui.Unindent()
        consumedWidth = consumedWidth + math.max(drawX - x, 0)
    end
    imgui.PopID()
    SetCursorPosSafe(imgui, x, y + consumedHeight)
    return consumedWidth, consumedHeight, bound._changed or drawChanged
end

--- Draws a single prepared UI node at the current ImGui cursor position.
---@param imgui table Active ImGui binding surface.
---@param node table Prepared UI node to render.
---@param uiState table|nil UI state used to resolve binds, writes, and visibility.
---@param width number|nil Available width hint for the node.
---@param customTypes table|nil Optional custom widget/layout registry extensions.
---@return boolean changed True when the node or one of its binds changed during rendering.
function ui.drawNode(imgui, node, uiState, width, customTypes)
    local widgetTypes, layoutTypes = MergeCustomTypes(customTypes)
    local startX = GetCursorPosXSafe(imgui)
    local startY = GetCursorPosYSafe(imgui)
    local _, consumedHeight, changed = DrawUiNodeAt(
        imgui,
        node,
        uiState,
        startX,
        startY,
        width,
        nil,
        widgetTypes,
        layoutTypes)
    SetCursorPosSafe(imgui, startX, startY + consumedHeight)
    return changed
end

--- Draws a list of prepared UI nodes sequentially from the current ImGui cursor position.
---@param imgui table Active ImGui binding surface.
---@param nodes table Ordered list of prepared UI nodes to render.
---@param uiState table|nil UI state used to resolve binds, writes, and visibility.
---@param width number|nil Available width hint for each node.
---@param customTypes table|nil Optional custom widget/layout registry extensions.
---@return boolean changed True when any rendered node or bind changed during rendering.
function ui.drawTree(imgui, nodes, uiState, width, customTypes)
    if type(nodes) ~= "table" then
        return false
    end
    local widgetTypes, layoutTypes = MergeCustomTypes(customTypes)
    local changed = false
    local startX = GetCursorPosXSafe(imgui)
    local currentY = GetCursorPosYSafe(imgui)
    for _, node in ipairs(nodes) do
        local _, consumedHeight, nodeChanged = DrawUiNodeAt(
            imgui,
            node,
            uiState,
            startX,
            currentY,
            width,
            nil,
            widgetTypes,
            layoutTypes)
        if nodeChanged then
            changed = true
        end
        currentY = currentY + consumedHeight
    end
    SetCursorPosSafe(imgui, startX, currentY)
    return changed
end


--- Collects all quick-UI widget nodes from a prepared UI tree.
---@param nodes table Ordered list of UI nodes to scan.
---@param out table|nil Optional output list to append quick nodes into.
---@param customTypes table|nil Optional custom widget/layout registry extensions.
---@return table out List containing every quick-UI widget node found in the tree.
function ui.collectQuick(nodes, out, customTypes)
    out = out or {}
    if type(nodes) ~= "table" then
        return out
    end
    local widgetTypes, layoutTypes = MergeCustomTypes(customTypes)
    for _, node in ipairs(nodes) do
        if type(node) == "table" then
            if widgetTypes[node.type] and node.quick == true then
                node._quickId = node._quickId or uiInternal.DeriveQuickUiNodeId(node)
                table.insert(out, node)
            end
            if layoutTypes[node.type] and type(node.children) == "table" then
                ui.collectQuick(node.children, out, customTypes)
            end
        end
    end
    return out
end

--- Derives the quick-UI identifier for a UI node.
---@param node table UI node to inspect.
---@return string|nil quickId Derived quick-UI identifier, or nil when the node has none.
function ui.getQuickId(node)
    return uiInternal.DeriveQuickUiNodeId(node)
end
