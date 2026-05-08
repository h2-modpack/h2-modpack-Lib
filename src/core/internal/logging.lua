local internal = AdamantModpackLib_Internal
local libConfig = internal.libConfig

local AllowedViolationSeverity = {
    error = true,
    warn = true,
    debug = true,
    ignore = true,
}

local DefaultViolationSeverity = {
    ["coordinator.invalid_registration"] = "error",
    ["coordinator.invalid_rebuild_callback"] = "error",
    ["definition.incomplete_manual_lifecycle"] = "error",
    ["definition.invalid_field_type"] = "debug",
    ["definition.invalid_args"] = "error",
    ["definition.missing_coordinated_id"] = "debug",
    ["definition.missing_mutation"] = "error",
    ["definition.unknown_key"] = "debug",
    ["definition.reserved_storage_alias"] = "error",
    ["game_object.invalid_args"] = "error",
    ["game_object.invalid_bucket"] = "error",
    ["game_object.invalid_factory"] = "error",
    ["host.invalid_create_opts"] = "error",
    ["host.invalid_standalone_binding"] = "error",
    ["host.coordinated_runtime_sync_failed"] = "warn",
    ["host.enable_transition_failed"] = "warn",
    ["host.session_commit_failed"] = "warn",
    ["host.standalone_startup_lifecycle_failed"] = "warn",
    ["host.structural_rebuild_unavailable"] = "error",
    ["hooks.invalid_registration"] = "error",
    ["hooks.inactive_override"] = "error",
    ["hooks.modutil_unavailable"] = "error",
    ["integrations.invalid_args"] = "error",
    ["lifecycle.on_settings_committed_failed"] = "warn",
    ["lifecycle.on_settings_committed_false"] = "warn",
    ["lifecycle.session_drift_detected"] = "warn",
    ["lifecycle.session_rollback_reapply_failed"] = "warn",
    ["overlays.invalid_registration"] = "error",

    ["session.unknown_reset_alias"] = "error",
    ["session.unknown_table_alias"] = "error",
    ["session.unknown_write_alias"] = "error",
    ["session.invalid_table_alias"] = "error",
    ["session.invalid_table_surface"] = "error",
    ["session.invalid_read_surface"] = "error",
    ["session.invalid_write_surface"] = "error",
    ["session.readonly_view_write"] = "error",

    ["store.invalid_create_args"] = "error",
    ["store.invalid_managed_store"] = "error",
    ["store.invalid_read_surface"] = "error",
    ["store.invalid_table_alias"] = "error",
    ["store.invalid_table_surface"] = "error",
    ["store.invalid_write_surface"] = "error",
    ["store.unknown_read_alias"] = "error",
    ["store.unknown_table_alias"] = "error",
    ["store.unknown_write_alias"] = "error",
    ["storage.duplicate_alias"] = "error",
    ["storage.hash_requires_persist"] = "error",
    ["storage.hash_requires_stage"] = "error",
    ["storage.invalid_axis_type"] = "error",
    ["storage.invalid_default"] = "error",
    ["storage.invalid_node"] = "error",
    ["storage.invalid_packed_bit"] = "error",
    ["storage.invalid_schema"] = "error",
    ["storage.invalid_table_row"] = "error",
    ["storage.missing_persisted_default"] = "error",
    ["storage.packed_requires_stage"] = "error",
    ["storage.packed_child_default_mismatch"] = "debug",
    ["storage.readonly_table_handle"] = "error",

    ["store.invalid_unstaged_write"] = "error",
}

local function FormatMessage(prefix, fmt, ...)
    return prefix .. (select("#", ...) > 0 and string.format(fmt, ...) or fmt)
end

internal.formatLogMessage = FormatMessage
internal.violationSeverity = internal.violationSeverity or {}

for id, severity in pairs(DefaultViolationSeverity) do
    if internal.violationSeverity[id] == nil then
        internal.violationSeverity[id] = severity
    end
end

function internal.violate(id, fmt, ...)
    assert(type(id) == "string" and id ~= "", "internal.violate: id must be a non-empty string")
    assert(type(fmt) == "string", "internal.violate: fmt must be a string")

    local severity = internal.violationSeverity[id] or "error"
    if not AllowedViolationSeverity[severity] then
        error(FormatMessage("[lib] violation.invalid_severity: ", "%s is configured with invalid severity '%s'", id, tostring(severity)), 2)
    end

    local message = FormatMessage("[lib] " .. id .. ": ", fmt, ...)
    if severity == "error" then
        error(message, 2)
    elseif severity == "warn" then
        print(message)
    elseif severity == "debug" and libConfig.DebugMode then
        print(message)
    end

    return severity, message
end
