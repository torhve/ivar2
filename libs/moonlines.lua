local M = {}

local path_meta = {}

local function pos_to_line(str, pos)
    local line = 1
    for _ in str:sub(1, pos):gmatch('\n') do line = line + 1 end
    return line
end

local function pos_for_line(source, line)
    local current = 1
    for i = 1, line - 1 do
        local nl = source:find('\n', current)
        if not nl then break end
        current = nl + 1
    end
    return current
end

local function find_lua_lines(ltable, offset)
    local matches = {}
    for lua_line, pos in pairs(ltable) do
        if pos == offset then
            table.insert(matches, lua_line)
        end
    end
    table.sort(matches)
    return matches
end

function M.loadfile(moonscript, path)
    local file = io.open(path)
    local source = file and file:read('*a') or ''
    if file then file:close() end

    local ltable
    local _, lt = moonscript.to_lua(source, {})
    ltable = lt
    if type(ltable) ~= 'table' then
        ltable = nil
    end

    path_meta[path] = {
        ltable = ltable or {},
        source = source,
    }

    local func, err = moonscript.loadfile(path)
    if not func then
        return nil, M.rewrite_parse_error(err, path, source, ltable)
    end
    return func
end

function M.rewrite_parse_error(msg, path, source, ltable)
    local lines = {}
    for line in msg:gmatch('[^\r\n]+') do table.insert(lines, line) end

    local result = {}
    for i, line in ipairs(lines) do
        local moon_line = line:match('^%s*%[(%d+)%]%s*>>')
        if moon_line then
            moon_line = tonumber(moon_line)
            local after_arrow = line:match('%]%s*>>%s*(.*)')
            if not after_arrow then after_arrow = '' end
            local prefix = path and path .. ':' or ''
            if ltable and next(ltable) and source then
                local offset = pos_for_line(source, moon_line)
                local lua_lines = find_lua_lines(ltable, offset)
                if #lua_lines > 0 then
                    local lua_str = table.concat(lua_lines, ',')
                    table.insert(result,
                        string.format(' %s[%d] (lua:%s) >> %s',
                            prefix, moon_line, lua_str, after_arrow))
                else
                    table.insert(result,
                        string.format(' %s[%d] >> %s', prefix, moon_line, after_arrow))
                end
            else
                table.insert(result,
                    string.format(' %s[%d] >> %s', prefix, moon_line, after_arrow))
            end
        else
            table.insert(result, line)
        end
    end

    return table.concat(result, '\n')
end

function M.rewrite_error(msg)
    local rewritten = msg:gsub('([^<%s]+%.moon):(%d+)', function(moon_path, lua_line_str)
        local lua_line = tonumber(lua_line_str)
        if not lua_line then return string.format('%s:%s', moon_path, lua_line_str) end

        local meta = path_meta[moon_path]
        if not meta or not meta.ltable then
            return string.format('%s:%s', moon_path, lua_line_str)
        end

        local offset = meta.ltable[lua_line]
        if not offset then
            for i = lua_line, 1, -1 do
                offset = meta.ltable[i]
                if offset then break end
            end
        end
        if not offset then
            return string.format('%s:%s', moon_path, lua_line_str)
        end

        local moon_line = pos_to_line(meta.source, offset)
        return string.format('%s:%d (lua:%d)', moon_path, moon_line, lua_line)
    end)

    return rewritten
end

function M.pcall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        return false, M.rewrite_error(result)
    end
    return true, result
end

return M
