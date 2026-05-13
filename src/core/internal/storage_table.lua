local internal = AdamantModpackLib_Internal
local storageInternal = internal.storage
local StorageTypes = storageInternal.types
local values = internal.values

local function ClampRowCount(node, count)
    count = math.floor(tonumber(count) or 0)
    if count < 0 then count = 0 end
    if node.minRows ~= nil and count < node.minRows then count = node.minRows end
    if node.maxRows ~= nil and count > node.maxRows then count = node.maxRows end
    return count
end

local function GetRowAliasNodes(node)
    return node and node.row and storageInternal.getAliases(node.row) or {}
end

local function GetRowRootNodes(node)
    return node and node.row and storageInternal.getRoots(node.row) or {}
end

local function CreateDefaultTableRow(node)
    local row = {}
    for _, root in ipairs(GetRowRootNodes(node)) do
        row[root.alias] = values.deepCopy(root.default)
    end
    return row
end

function storageInternal.PrepareTableNode(node, prefix)
    if type(node.row) ~= "table" then
        return
    end

    for index, rowNode in ipairs(node.row) do
        local rowPrefix = prefix .. " row[" .. index .. "]"
        if type(rowNode) == "table" then
            if rowNode.type == "table" then
                internal.violate("storage.invalid_table_row", "%s: nested table storage is not supported", rowPrefix)
            end
            if rowNode.persist ~= nil then
                internal.violate(
                    "storage.invalid_table_row",
                    "%s: row storage cannot declare persist; table root owns persistence",
                    rowPrefix
                )
            end
            if rowNode.stage ~= nil then
                internal.violate("storage.invalid_table_row", "%s: row storage cannot declare stage; table root owns staging", rowPrefix)
            end
            if rowNode.hash ~= nil then
                internal.violate("storage.invalid_table_row", "%s: row storage cannot declare hash; table root owns hashing", rowPrefix)
            end
        end
    end

    storageInternal.validate(node.row, prefix .. " row")

    node.minRows = ClampRowCount({ minRows = 0 }, node.minRows or 0)
    node.maxRows = node.maxRows ~= nil and ClampRowCount({ minRows = 0 }, node.maxRows) or nil
    if node.maxRows ~= nil and node.minRows > node.maxRows then
        node.minRows = node.maxRows
    end
    node.defaultRows = ClampRowCount(node, node.defaultRows or node.minRows or 0)
    node.default = storageInternal.NormalizeTableValue(node, nil)
    node._tableDefaultPrepared = true
end

function storageInternal.NormalizeTableRow(node, rowValue)
    local row = CreateDefaultTableRow(node)
    if type(rowValue) ~= "table" then
        return row
    end
    local aliasNodes = GetRowAliasNodes(node)

    for _, root in ipairs(GetRowRootNodes(node)) do
        if rowValue[root.alias] ~= nil then
            row[root.alias] = storageInternal.NormalizeStorageValue(root, rowValue[root.alias])
        end
    end

    local rowBackend = {
        readRoot = function(root)
            local value = row[root.alias]
            if value == nil then
                value = values.deepCopy(root.default)
            end
            return storageInternal.NormalizeStorageValue(root, value)
        end,
        writeRoot = function(root, value)
            row[root.alias] = storageInternal.NormalizeStorageValue(root, value)
            return true
        end,
    }

    for alias, value in pairs(rowValue) do
        if aliasNodes[alias] ~= nil then
            storageInternal.writeAlias(aliasNodes, rowBackend, alias, value)
        end
    end

    return row
end

function storageInternal.NormalizeTableValue(node, value)
    local rows = {}
    local source = type(value) == "table" and value or nil
    local count = source and #source or node.defaultRows or 0
    count = ClampRowCount(node, count)

    for index = 1, count do
        rows[index] = storageInternal.NormalizeTableRow(node, source and source[index] or nil)
    end
    return rows
end

local function EncodeLengthPrefixed(value)
    value = tostring(value or "")
    return tostring(#value) .. ":" .. value
end

local function DecodeLengthPrefixed(str, pos)
    local lenText, nextPos = string.match(str, "^(%d+):()", pos)
    if not lenText then
        return nil, nil
    end
    local len = tonumber(lenText) or 0
    local valueStart = nextPos
    local valueEnd = valueStart + len - 1
    if valueEnd > #str then
        return nil, nil
    end
    return string.sub(str, valueStart, valueEnd), valueEnd + 1
end

function storageInternal.SerializeTableValue(node, value)
    local rows = storageInternal.NormalizeTableValue(node, value)
    local parts = { tostring(#rows) .. ":" }
    for _, row in ipairs(rows) do
        for _, root in ipairs(GetRowRootNodes(node)) do
            local storageType = StorageTypes[root.type]
            local encoded = storageType.toHash(root, row[root.alias])
            parts[#parts + 1] = EncodeLengthPrefixed(encoded)
        end
    end
    return table.concat(parts)
end

function storageInternal.DeserializeTableValue(node, str)
    if type(str) ~= "string" then
        return storageInternal.NormalizeTableValue(node, nil)
    end

    local countText, pos = string.match(str, "^(%d+):()")
    if not countText then
        return storageInternal.NormalizeTableValue(node, nil)
    end

    local rows = {}
    local count = ClampRowCount(node, tonumber(countText) or 0)
    local roots = GetRowRootNodes(node)
    for rowIndex = 1, count do
        local row = {}
        for _, root in ipairs(roots) do
            local encoded
            encoded, pos = DecodeLengthPrefixed(str, pos)
            if encoded == nil then
                return storageInternal.NormalizeTableValue(node, nil)
            end
            local storageType = StorageTypes[root.type]
            row[root.alias] = storageType.fromHash(root, encoded)
        end
        rows[rowIndex] = storageInternal.NormalizeTableRow(node, row)
    end
    return storageInternal.NormalizeTableValue(node, rows)
end

function storageInternal.CreateTableHandle(node, opts)
    opts = opts or {}
    local aliasNodes = GetRowAliasNodes(node)
    local rowHandles = {}

    local function readRows()
        local rows = opts.readRoot(node)
        if opts.normalizedRoot == true then
            return type(rows) == "table" and rows or node.default
        end
        return storageInternal.NormalizeTableValue(node, rows)
    end

    local function copyRows()
        if opts.normalizedRoot == true then
            return values.deepCopy(readRows())
        end
        return readRows()
    end

    local function writeRows(rows)
        if opts.writeRoot == nil then
            internal.violate("storage.readonly_table_handle", "table storage handle is read-only")
        end
        return opts.writeRoot(node, storageInternal.NormalizeTableValue(node, rows))
    end

    local function getRowCount(rows)
        return ClampRowCount(node, type(rows) == "table" and #rows or 0)
    end

    local function readRow(rows, rowIndex)
        rowIndex = math.floor(tonumber(rowIndex) or 0)
        if rowIndex < 1 or rowIndex > getRowCount(rows) then
            return nil, rowIndex
        end
        return rows[rowIndex], rowIndex
    end

    local function readRowAlias(row, alias)
        local rowBackend = {
            readRoot = function(root)
                local value = row[root.alias]
                if value == nil then
                    return values.deepCopy(root.default)
                end
                if opts.normalizedRoot == true then
                    return value
                end
                return storageInternal.NormalizeStorageValue(root, value)
            end,
            onUnknownRead = function(rowAlias)
                internal.violate(
                    "storage.unknown_table_row_alias",
                    "table storage '%s': unknown row alias '%s'",
                    tostring(node.alias),
                    tostring(rowAlias)
                )
            end,
        }
        return storageInternal.readAlias(aliasNodes, rowBackend, alias)
    end

    local function writeRowAlias(row, alias, value)
        local rowBackend = {
            readRoot = function(root)
                local raw = row[root.alias]
                if raw == nil then
                    return values.deepCopy(root.default)
                end
                if opts.normalizedRoot == true then
                    return raw
                end
                return storageInternal.NormalizeStorageValue(root, raw)
            end,
            writeRoot = function(root, rootValue)
                row[root.alias] = storageInternal.NormalizeStorageValue(root, rootValue)
                return true
            end,
            onUnknownWrite = function(rowAlias)
                internal.violate(
                    "storage.unknown_table_row_alias",
                    "table storage '%s': unknown row alias '%s'",
                    tostring(node.alias),
                    tostring(rowAlias)
                )
            end,
        }
        return storageInternal.writeAlias(aliasNodes, rowBackend, alias, value)
    end

    local handle = {}

    local function ValidateReceiver(receiver, methodName)
        if receiver ~= handle then
            internal.violate(
                "storage.invalid_table_handle_args",
                "table storage '%s': invalid receiver for %s",
                tostring(node.alias),
                tostring(methodName)
            )
        end
    end

    local function ValidateRowIndex(rowIndex, methodName)
        if type(rowIndex) ~= "number" then
            internal.violate(
                "storage.invalid_table_handle_args",
                "table storage '%s': %s expects numeric rowIndex",
                tostring(node.alias),
                tostring(methodName)
            )
        end
    end

    local function ValidateAlias(alias, methodName)
        if type(alias) ~= "string" or alias == "" then
            internal.violate(
                "storage.invalid_table_handle_args",
                "table storage '%s': %s expects non-empty row alias",
                tostring(node.alias),
                tostring(methodName)
            )
        end
    end

    function handle.count(self)
        ValidateReceiver(self, "count")
        return getRowCount(readRows())
    end

    function handle.read(self, rowIndex, alias)
        ValidateReceiver(self, "read")
        ValidateRowIndex(rowIndex, "read")
        ValidateAlias(alias, "read")
        local row = readRow(readRows(), rowIndex)
        if not row then
            return nil
        end
        return readRowAlias(row, alias)
    end

    function handle.row(self, rowIndex)
        ValidateReceiver(self, "row")
        ValidateRowIndex(rowIndex, "row")
        local row = readRow(readRows(), rowIndex)
        return row and values.deepCopy(row) or nil
    end

    function handle.rows(self)
        ValidateReceiver(self, "rows")
        return values.deepCopy(readRows())
    end

    function handle.rowHandle(self, rowIndex)
        ValidateReceiver(self, "rowHandle")
        ValidateRowIndex(rowIndex, "rowHandle")
        rowIndex = math.floor(tonumber(rowIndex) or 0)
        local cached = rowHandles[rowIndex]
        if cached then
            return cached
        end

        local currentReadRow = nil
        local rowReadBackend = {
            readRoot = function(root)
                local value = currentReadRow[root.alias]
                if value == nil then
                    return values.deepCopy(root.default)
                end
                if opts.normalizedRoot == true then
                    return value
                end
                return storageInternal.NormalizeStorageValue(root, value)
            end,
            onUnknownRead = function(rowAlias)
                internal.violate(
                    "storage.unknown_table_row_alias",
                    "table storage '%s': unknown row alias '%s'",
                    tostring(node.alias),
                    tostring(rowAlias)
                )
            end,
        }

        local rowHandle = {
            read = function(alias)
                ValidateAlias(alias, "rowHandle.read")
                local row = readRow(readRows(), rowIndex)
                if not row then
                    return nil
                end
                currentReadRow = row
                local value = storageInternal.readAlias(aliasNodes, rowReadBackend, alias)
                currentReadRow = nil
                return value
            end,
            getAliasSchema = function(alias)
                ValidateAlias(alias, "rowHandle.getAliasSchema")
                return aliasNodes[alias]
            end,
        }

        if opts.writeRoot ~= nil then
            local currentWriteRow = nil
            local rowWriteBackend = {
                readRoot = function(root)
                    local raw = currentWriteRow[root.alias]
                    if raw == nil then
                        return values.deepCopy(root.default)
                    end
                    if opts.normalizedRoot == true then
                        return raw
                    end
                    return storageInternal.NormalizeStorageValue(root, raw)
                end,
                writeRoot = function(root, rootValue)
                    currentWriteRow[root.alias] = storageInternal.NormalizeStorageValue(root, rootValue)
                    return true
                end,
                onUnknownWrite = function(rowAlias)
                    internal.violate(
                        "storage.unknown_table_row_alias",
                        "table storage '%s': unknown row alias '%s'",
                        tostring(node.alias),
                        tostring(rowAlias)
                    )
                end,
            }

            rowHandle.write = function(alias, value)
                ValidateAlias(alias, "rowHandle.write")
                local rows = copyRows()
                local row = readRow(rows, rowIndex)
                if not row then
                    return false
                end
                currentWriteRow = row
                local changed = storageInternal.writeAlias(aliasNodes, rowWriteBackend, alias, value)
                currentWriteRow = nil
                if changed then
                    writeRows(rows)
                end
                return changed
            end

            rowHandle.reset = function(alias)
                ValidateAlias(alias, "rowHandle.reset")
                local rows = copyRows()
                local row = readRow(rows, rowIndex)
                if not row then
                    return false
                end
                local aliasNode = aliasNodes[alias]
                if not aliasNode then
                    internal.violate(
                        "storage.unknown_table_row_alias",
                        "table storage '%s': unknown row alias '%s'",
                        tostring(node.alias),
                        tostring(alias)
                    )
                end
                currentWriteRow = row
                local changed = storageInternal.writeAlias(aliasNodes, rowWriteBackend, alias, values.deepCopy(aliasNode.default))
                currentWriteRow = nil
                if changed then
                    writeRows(rows)
                end
                return changed
            end
        end

        rowHandles[rowIndex] = rowHandle
        return rowHandle
    end

    if opts.writeRoot ~= nil then
        function handle.write(self, rowIndex, alias, value)
            ValidateReceiver(self, "write")
            ValidateRowIndex(rowIndex, "write")
            ValidateAlias(alias, "write")
            local rows = copyRows()
            local row = readRow(rows, rowIndex)
            if not row then
                return false
            end
            local changed = writeRowAlias(row, alias, value)
            if changed then
                writeRows(rows)
            end
            return changed
        end

        function handle.reset(self, rowIndex, alias)
            ValidateReceiver(self, "reset")
            ValidateRowIndex(rowIndex, "reset")
            ValidateAlias(alias, "reset")
            local rows = copyRows()
            local row = readRow(rows, rowIndex)
            if not row then
                return false
            end
            local aliasNode = aliasNodes[alias]
            if not aliasNode then
                internal.violate(
                    "storage.unknown_table_row_alias",
                    "table storage '%s': unknown row alias '%s'",
                    tostring(node.alias),
                    tostring(alias)
                )
            end
            local changed = writeRowAlias(row, alias, values.deepCopy(aliasNode.default))
            if changed then
                writeRows(rows)
            end
            return changed
        end

        function handle.resetRow(self, rowIndex)
            ValidateReceiver(self, "resetRow")
            ValidateRowIndex(rowIndex, "resetRow")
            local rows = copyRows()
            local _, normalizedIndex = readRow(rows, rowIndex)
            if normalizedIndex < 1 or normalizedIndex > #rows then
                return false
            end
            rows[normalizedIndex] = CreateDefaultTableRow(node)
            return writeRows(rows) ~= false
        end

        function handle.append(self, rowValues)
            ValidateReceiver(self, "append")
            local rows = copyRows()
            if node.maxRows ~= nil and #rows >= node.maxRows then
                return false
            end
            rows[#rows + 1] = storageInternal.NormalizeTableRow(node, rowValues)
            return writeRows(rows) ~= false
        end

        function handle.insert(self, rowIndex, rowValues)
            ValidateReceiver(self, "insert")
            ValidateRowIndex(rowIndex, "insert")
            local rows = copyRows()
            if node.maxRows ~= nil and #rows >= node.maxRows then
                return false
            end
            rowIndex = math.floor(tonumber(rowIndex) or (#rows + 1))
            if rowIndex < 1 then rowIndex = 1 end
            if rowIndex > #rows + 1 then rowIndex = #rows + 1 end
            table.insert(rows, rowIndex, storageInternal.NormalizeTableRow(node, rowValues))
            return writeRows(rows) ~= false
        end

        function handle.remove(self, rowIndex)
            ValidateReceiver(self, "remove")
            ValidateRowIndex(rowIndex, "remove")
            local rows = copyRows()
            rowIndex = math.floor(tonumber(rowIndex) or 0)
            if rowIndex < 1 or rowIndex > #rows then
                return false
            end
            table.remove(rows, rowIndex)
            return writeRows(rows) ~= false
        end

        function handle.clear(self)
            ValidateReceiver(self, "clear")
            return writeRows({}) ~= false
        end
    end

    return handle
end
