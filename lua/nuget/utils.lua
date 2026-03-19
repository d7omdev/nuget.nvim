local utils = {}

function utils.humanize(n)
    if n >= 1000000000 then
        return string.format("%.1fb", n / 1000000000)
    elseif n >= 1000000 then
        return string.format("%.1fm", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fk", n / 1000)
    else
        return tostring(n)
    end
end

local function parse_version(v)
    local base = v:match("^([%d%.]+)") or v
    local parts = {}
    for n in base:gmatch("%d+") do
        table.insert(parts, tonumber(n))
    end
    return parts
end

function utils.version_lt(a, b)
    local pa, pb = parse_version(a), parse_version(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y end
    end
    return false
end

function utils.sort_versions(versions, newest_first)
    table.sort(versions, function(a, b)
        if newest_first then return utils.version_lt(b, a) end
        return utils.version_lt(a, b)
    end)
end

function utils.version_ordinal(v)
    local parts = {}
    for n in v:gmatch("%d+") do
        table.insert(parts, string.format("%08d", tonumber(n)))
    end
    return table.concat(parts, ".")
end

return utils
