local internal = AdamantModpackLib_Internal
local libConfig = internal.libConfig
local logging = internal.logging

local function FormatMessage(prefix, fmt, ...)
    return prefix .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt)
end

logging.formatMessage = FormatMessage

function logging.warnIf(fmt, ...)
    if not libConfig.DebugMode then
        return
    end
    print(FormatMessage("[lib] ", fmt, ...))
end

function logging.warn(fmt, ...)
    print(FormatMessage("[lib] ", fmt, ...))
end
