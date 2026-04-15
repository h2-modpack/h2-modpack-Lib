local internal = AdamantModpackLib_Internal

public.registry = public.registry or {}
public.registry.storage       = public.registry.storage       or {}
public.registry.widgets       = public.registry.widgets       or {}
public.registry.widgetHelpers = public.registry.widgetHelpers or {}
public.registry.layouts       = public.registry.layouts       or {}
internal.ui = internal.ui or {}
internal.widgets = internal.widgets or {}

import 'field_registry/internal/ui.lua'
import 'field_registry/storage.lua'
import 'field_registry/internal/widgets.lua'
import 'field_registry/widgets/init.lua'
import 'field_registry/layouts.lua'
import 'field_registry/internal/registry.lua'
import 'field_registry/ui.lua'

public.registry.validate = internal.registry.validateRegistries
public.registry.validate()
