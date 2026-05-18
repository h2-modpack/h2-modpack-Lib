local deps = ...

public.widgets = public.widgets or {}
local imguiHelpers = import 'core/widgets/imgui_helpers.lua'
local widgetHelpers = import('core/widgets/widget_helpers.lua', nil, {
    logging = deps.logging,
    storage = deps.storage,
    imguiHelpers = imguiHelpers,
})
import('core/widgets/base.lua', nil, widgetHelpers)
import('core/widgets/inputs.lua', nil, widgetHelpers)
import('core/widgets/dropdowns.lua', nil, widgetHelpers)
import('core/widgets/radios.lua', nil, widgetHelpers)
import('core/widgets/steppers.lua', nil, widgetHelpers)
import('core/widgets/checkboxes.lua', nil, widgetHelpers)
import('core/widgets/buttons.lua', nil, widgetHelpers)

import 'core/widgets/nav.lua'
