local internal = AdamantModpackLib_Internal
local registry = internal.registry
local WidgetTypes = public.registry.widgets
local LayoutTypes = public.registry.layouts

local function AssertRegistryContracts(registryTable, required, label)
    for typeName, item in pairs(registryTable) do
        if type(item) ~= "table" then
            error(("%s type '%s' must be a table"):format(label, tostring(typeName)), 0)
        end
        for _, method in ipairs(required) do
            if type(item[method]) ~= "function" then
                error(("%s type '%s' is missing required method '%s'"):format(
                    label, tostring(typeName), method), 0)
            end
        end
    end
end

local function AssertWidgetContracts(registryTable, label)
    for typeName, item in pairs(registryTable) do
        if type(item) ~= "table" then
            error(("%s type '%s' must be a table"):format(label, tostring(typeName)), 0)
        end
        if type(item.validate) ~= "function" then
            error(("%s type '%s' is missing required method 'validate'"):format(
                label, tostring(typeName)), 0)
        end
        if type(item.draw) ~= "function" then
            error(("%s type '%s' is missing required method 'draw'"):format(
                label, tostring(typeName)), 0)
        end
    end
end

function registry.ValidateCustomTypes(customTypes, label)
    if type(customTypes) ~= "table" then
        error((label or "module") .. ": definition.customTypes must be a table", 0)
    end
    local widgets = customTypes.widgets
    local layouts = customTypes.layouts
    if widgets ~= nil then
        if type(widgets) ~= "table" then
            error((label or "module") .. ": customTypes.widgets must be a table", 0)
        end
        for typeName, item in pairs(widgets) do
            if WidgetTypes[typeName] then
                error(("%s: customTypes.widgets '%s' collides with built-in widget type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            if LayoutTypes[typeName] then
                error(("%s: customTypes.widgets '%s' collides with built-in layout type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            AssertWidgetContracts({ [typeName] = item }, "Widget")
            if type(item) == "table" and type(item.binds) ~= "table" then
                error(("%s: customTypes.widgets '%s' must declare a binds table"):format(
                    label or "module", tostring(typeName)), 0)
            end
        end
    end
    if layouts ~= nil then
        if type(layouts) ~= "table" then
            error((label or "module") .. ": customTypes.layouts must be a table", 0)
        end
        for typeName, item in pairs(layouts) do
            if WidgetTypes[typeName] then
                error(("%s: customTypes.layouts '%s' collides with built-in widget type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            if LayoutTypes[typeName] then
                error(("%s: customTypes.layouts '%s' collides with built-in layout type"):format(
                    label or "module", tostring(typeName)), 0)
            end
            AssertRegistryContracts({ [typeName] = item }, { "validate", "render" }, "Layout")
        end
    end
end

function registry.MergeCustomTypes(customTypes)
    local mergedCustomTypesCache = registry._mergedCustomTypesCache
    if not mergedCustomTypesCache then
        mergedCustomTypesCache = setmetatable({}, { __mode = "k" })
        registry._mergedCustomTypesCache = mergedCustomTypesCache
    end
    if not customTypes then
        return WidgetTypes, LayoutTypes
    end
    local cached = mergedCustomTypesCache[customTypes]
    if cached then
        return cached.widgets, cached.layouts
    end
    local mergedWidgets = {}
    for k, v in pairs(WidgetTypes) do mergedWidgets[k] = v end
    if type(customTypes.widgets) == "table" then
        for k, v in pairs(customTypes.widgets) do mergedWidgets[k] = v end
    end
    local mergedLayouts = {}
    for k, v in pairs(LayoutTypes) do mergedLayouts[k] = v end
    if type(customTypes.layouts) == "table" then
        for k, v in pairs(customTypes.layouts) do mergedLayouts[k] = v end
    end
    mergedCustomTypesCache[customTypes] = {
        widgets = mergedWidgets,
        layouts = mergedLayouts,
    }
    return mergedWidgets, mergedLayouts
end

function registry.validateRegistries()
    local storageTypes = public.registry.storage
    local widgetTypes  = public.registry.widgets
    local layoutTypes  = public.registry.layouts

    for typeName, item in pairs(storageTypes) do
        if type(item) ~= "table" then
            error(("Storage type '%s' must be a table"):format(tostring(typeName)), 0)
        end
        for _, method in ipairs({ "validate", "normalize", "toHash", "fromHash" }) do
            if type(item[method]) ~= "function" then
                error(("Storage type '%s' is missing required method '%s'"):format(
                    tostring(typeName), method), 0)
            end
        end
    end

    for typeName, item in pairs(widgetTypes) do
        if type(item) ~= "table" then
            error(("Widget type '%s' must be a table"):format(tostring(typeName)), 0)
        end
        if type(item.validate) ~= "function" then
            error(("Widget type '%s' is missing required method 'validate'"):format(
                tostring(typeName)), 0)
        end
        if type(item.draw) ~= "function" then
            error(("Widget type '%s' is missing required method 'draw'"):format(
                tostring(typeName)), 0)
        end
    end

    for typeName, item in pairs(layoutTypes) do
        if type(item) ~= "table" then
            error(("Layout type '%s' must be a table"):format(tostring(typeName)), 0)
        end
        for _, method in ipairs({ "validate", "render" }) do
            if type(item[method]) ~= "function" then
                error(("Layout type '%s' is missing required method '%s'"):format(
                    tostring(typeName), method), 0)
            end
        end
    end

    for typeName, widgetType in pairs(widgetTypes) do
        if type(widgetType.binds) ~= "table" then
            error(("Widget type '%s' must declare a binds table"):format(tostring(typeName)), 0)
        end
    end
    return true
end
