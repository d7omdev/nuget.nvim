local notify                          = require("nuget.notify")
local utils                           = require("nuget.utils")
local M                               = {}

--- Run `dotnet list <target> package --no-restore --format json`.
--- Calls callback(map) where map = { ["Pkg.Id"] = { version, projects = [...] } }.
--- target may be a .csproj or .sln path.
--- opts
---   .method   dotnet | parse - method for retrieving installed nugets from project files
---   .dotnet_bin binary to use for dotnet commands. default is "dotnet"
M.get_installed_packages              = function(target, opts, callback)
    local ext    = vim.fn.fnamemodify(target, ":e")
    local method = (opts and opts.method) or "parse"
    if method == "dotnet" then
        M.get_installed_packages_dotnet(target, opts, callback)
    elseif ext == "sln" then
        M.get_installed_packages_parse_sln(target, opts, callback)
    else
        M.get_installed_packages_parse_csproj(target, opts, callback)
    end
end

M.get_installed_packages_parse_sln    = function(target, opts, callback)
    local sln_dir = vim.fn.fnamemodify(target, ":h")
    local lines   = vim.fn.readfile(target)
    local map     = {}
    for _, line in ipairs(lines) do
        local rel_path = line:match('"([^"]+%.csproj)"')
        if rel_path then
            rel_path = rel_path:gsub("\\", "/")
            local abs_path = sln_dir .. "/" .. rel_path
            M.get_installed_packages_parse_csproj(abs_path, opts, function(proj_map)
                for id, entry in pairs(proj_map) do
                    if not map[id] then
                        map[id] = { version = entry.version, projects = {} }
                    end
                    vim.list_extend(map[id].projects, entry.projects)
                end
            end)
        end
    end
    callback(map)
end

M.get_installed_packages_parse_csproj = function(target, opts, callback)
    local lines   = vim.fn.readfile(target)
    local content = table.concat(lines, "\n")
    local map     = {}
    for id, version in content:gmatch('<PackageReference%s+Include="([^"]+)"%s+Version="([^"]+)"') do
        map[id] = { version = version, projects = { target } }
    end
    for id in content:gmatch('<PackageReference%s+Include="([^"]+)"') do
        if not map[id] then
            local version = content:match('<PackageReference[^>]+Include="' ..
                id .. '"[^>]*>%s*<Version>([^<]+)</Version>')
            map[id] = { version = version, projects = { target } }
        end
    end
    callback(map)
end

M.get_installed_packages_dotnet       = function(target, opts, callback)
    local cwd = vim.fn.fnamemodify(target, ":h")
    local rel = vim.fn.fnamemodify(target, ":t")
    local cmd = { opts.dotnet_bin or "dotnet", "list", rel, "package", "--no-restore", "--format", "json" }

    vim.system(cmd, { cwd = cwd }, function(result)
        local ok, decoded = pcall(vim.json.decode, result.stdout or "")
        if not ok or not decoded then
            callback({})
            return
        end

        local map = {}
        for _, proj in ipairs(decoded.projects or {}) do
            local proj_path = proj.path or proj.name or "?"
            for _, fw in ipairs(proj.frameworks or {}) do
                for _, pkg in ipairs(fw.topLevelPackages or {}) do
                    local id = pkg.id
                    if id then
                        if not map[id] then
                            map[id] = {
                                version  = pkg.resolvedVersion or pkg.requestedVersion,
                                projects = {},
                            }
                        end
                        table.insert(map[id].projects, proj_path)
                    end
                end
            end
        end
        callback(map)
    end)
end

local function build_search_command(query, opts)
    local cmd = { opts.dotnet_bin or "dotnet", "package", "search", query }
    for _, source in ipairs(opts.sources or {}) do
        table.insert(cmd, "--source")
        table.insert(cmd, source)
    end
    if opts.prerelease then table.insert(cmd, "--prerelease") end
    if opts.exact_match then
        table.insert(cmd, "--exact-match")
    else
        table.insert(cmd, "--take")
        table.insert(cmd, "10")
    end
    table.insert(cmd, "--format")
    table.insert(cmd, "json")
    table.insert(cmd, "--verbosity")
    table.insert(cmd, opts.verbosity or "detailed")
    return cmd
end

local version_cache = {}

local function cache_key(id, opts)
    return id:lower() .. (opts.prerelease and ":pre" or "")
end

M.get_latest_versions = function(id, opts, callback)
    local key = cache_key(id, opts)
    local progress = notify.make_progress("get latest " .. key)

    if version_cache[key] then
        progress.finish("found in cache")
        callback(version_cache[key])
        return
    end

    local cmd = build_search_command(id, vim.tbl_extend("force", opts, {
        exact_match = true,
        verbosity   = "quiet",
    }))

    progress.report("dotnet search" .. key)
    vim.system(cmd, {}, function(result)
        if result.code ~= 0 then
            progress.finish("failed with exit code " .. tostring(result.code))
            return
        end
        local ok, decoded = pcall(vim.json.decode, result.stdout or "")
        if not ok or not decoded then
            progress.finish("failed to decode result")
            return
        end

        local versions = {}
        for _, source in ipairs(decoded.searchResult or {}) do
            for _, pkg in ipairs(source.packages or {}) do
                if pkg.id and pkg.id:lower() == id:lower() then
                    table.insert(versions, pkg.version)
                end
            end
        end

        if #versions == 0 then
            progress.finish("Found 0 versions")
            return
        end

        utils.sort_versions(versions, true)
        local entry = { latest = versions[1], versions = versions }
        version_cache[key] = entry
        progress.finish("Found " .. tostring(#versions) .. " versions")
        callback(entry)
    end)
end

M.purge_version_cache = function(id, opts)
    if id then
        version_cache[cache_key(id, opts or {})] = nil
    else
        version_cache = {}
    end
end

local function parse_nuget_search_results(json_str)
    local ok, decoded = pcall(vim.json.decode, json_str)
    if not ok or not decoded then return {} end
    local packages = {}
    for _, source in ipairs(decoded.searchResult or {}) do
        for _, pkg in ipairs(source.packages or {}) do
            if type(pkg) == "table" and pkg.id then
                table.insert(packages, {
                    id          = pkg.id,
                    version     = pkg.latestVersion or "unknown",
                    downloads   = pkg.totalDownloads or 0,
                    owners      = pkg.owners or "",
                    description = pkg.description or "",
                    project_url = pkg.projectUrl or "",
                })
            end
        end
    end
    return packages
end

M.install_package = function(target, id, version, opts, callback)
    local label    = id .. " " .. version
    local progress = notify.make_progress("Installing " .. label)

    local cmd      = { opts.dotnet_bin or "dotnet", "add", target, "package", id, "--version", version }
    for _, source in ipairs(opts.sources or {}) do
        vim.list_extend(cmd, { "--source", source })
    end

    vim.system(cmd, {
        stdout = function(_, data)
            if not data then return end
            for _, line in ipairs(vim.split(data, "\n", { plain = true })) do
                if line ~= "" then
                    vim.schedule(function() progress.report(line) end)
                end
            end
        end,
    }, function(result)
        vim.schedule(function()
            if result.code == 0 then
                progress.finish("Installed " .. label)
            else
                progress.cancel("Failed " .. label)
            end
            callback(result.code == 0, result.stdout, result.stderr)
        end)
    end)
end

-- finds all csprojs, then returns a map
-- map[csproj_path] = { sln = sln_path | nil }
M.build_project_map = function(opts)
    local cwd = vim.fn.getcwd()
    local lines = vim.fn.systemlist(
        "fd --type f --color never -e csproj -e sln --exclude .git -L", cwd)
    local sln_files = {}
    local csproj_files = {}
    for _, line in ipairs(lines) do
        if line ~= "" then
            if line:match("%.sln$") then
                table.insert(sln_files, line)
            else
                table.insert(csproj_files, line)
            end
        end
    end
    local map = {}
    for _, csproj in ipairs(csproj_files) do
        map[csproj] = { sln = nil }
    end
    for _, sln in ipairs(sln_files) do
        local sln_dir   = vim.fn.fnamemodify(sln, ":h")
        local sln_lines = vim.fn.systemlist("dotnet sln " .. vim.fn.shellescape(cwd .. "/" .. sln) .. " list")
        for _, line in ipairs(sln_lines) do
            local rel = line:gsub("\\", "/"):match("([^\r]+%.csproj)")
            if rel then
                local joined = sln_dir ~= "." and (sln_dir .. "/" .. rel) or rel
                local norm = vim.fn.fnamemodify(joined, ":.")
                if map[norm] and map[norm].sln == nil then
                    map[norm].sln = sln
                end
            end
        end
    end
    return map
end

return M
