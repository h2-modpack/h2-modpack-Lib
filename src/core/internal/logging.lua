local internal = AdamantModpackLib_Internal
local libConfig = internal.libConfig

local function FormatMessage(prefix, fmt, ...)
    return prefix .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt)
end

internal.formatLogMessage = FormatMessage

function internal.libWarnIf(fmt, ...)
    if not libConfig.DebugMode then
        return
    end
    print(FormatMessage("[lib] ", fmt, ...))
end

function internal.libWarn(fmt, ...)
    print(FormatMessage("[lib] ", fmt, ...))
end
