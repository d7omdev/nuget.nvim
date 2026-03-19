local notify                           = require("nuget.notify")
local utils                            = require("nuget.utils")
local M                                = {}

---@class dotnet_opts
---@field dotnet_bin string binary to use for dotnet commands
---@field sources string[]? additional NuGet.config sources
---@field cwd string? perform operations from this directory

---@class (exact) dotnet_package
---@field mixed_versions boolean whether the projects contain multiple different versions
---@field projects { path: string, version: string } projects that contain this package
---@field version string the highest version used by any of the projects

---@alias dotnet_packages { [string]: dotnet_package }

---@class (exact) dotnet_version
---@field latest string latest version
---@field versions string[] all versions, sorted
---@field description string?
---@field project_url string?

---@alias dotnet_versions { [string]: dotnet_version }

---@alias dotnet_map { [string]: { sln: string? }}

-- Retrieve all the packages used by the given target
---@param target string .sln or .csproj file to retrieve packages from. .sln means get packages from all related csprojs.
---@param opts dotnet_opts
---@param method "parse" | "dotnet" | nil which method to use to retrieve the packages. Parse the files or use `dotnet list`
---@param callback fun(packages: dotnet_packages): nil called once with the retrieved packages
M.get_installed_packages               = function(target, opts, method, callback)
    local ext = vim.fn.fnamemodify(target, ":e")
    method    = method or "parse"
    if method == "dotnet" then
        M.get_installed_packages_dotnet(target, opts, callback)
    elseif ext == "sln" then
        M.get_installed_packages_parse_sln(target, opts, callback)
    else
        M.get_installed_packages_parse_csproj(target, opts, callback)
    end
end

-- Retrieve all the packages used by the given target solution by parsing the files
---@param target string .sln file to retrieve packages from (via all child csprojs)
---@param opts dotnet_opts
---@param callback fun(packages: { [string]:  dotnet_package } ): nil called once with the retrieved packages
M.get_installed_packages_parse_sln     = function(target, opts, callback)
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
                        map[id] = { projects = {}, mixed_versions = false }
                    end
                    table.insert(map[id].projects, entry.projects[1])
                end
            end)
        end
    end
    for _, entry in pairs(map) do
        local first = entry.projects[1] and entry.projects[1].version
        for _, proj in ipairs(entry.projects) do
            if proj.version ~= first then
                entry.mixed_versions = true
                break
            end
        end
        local versions = vim.tbl_map(function(p) return p.version end, entry.projects)
        table.sort(versions, utils.version_lt)
        entry.version = versions[1]
    end
    callback(map)
end

-- Retrieve all the packages used by the given target csproj by parsing the file
---@param target string .csproj file to retrieve packages from
---@param opts dotnet_opts
---@param callback fun(packages: dotnet_packages ): nil called once with the retrieved packages
M.get_installed_packages_parse_csproj  = function(target, opts, callback)
    local lines   = vim.fn.readfile(target)
    local content = table.concat(lines, "\n")
    local map     = {}
    for id, version in content:gmatch('<PackageReference%s+Include="([^"]+)"%s+Version="([^"]+)"') do
        map[id] = { projects = { { path = target, version = version } }, mixed_versions = false, version = version }
    end
    for id in content:gmatch('<PackageReference%s+Include="([^"]+)"') do
        if not map[id] then
            local version = content:match('<PackageReference[^>]+Include="' ..
                id .. '"[^>]*>%s*<Version>([^<]+)</Version>')
            map[id] = { projects = { { path = target, version = version } }, mixed_versions = false, version = version }
        end
    end
    callback(map)
end

-- Retrieve all the packages used by the given target csprojs by parsing the files
---@param targets string[] .csproj file to retrieve packages from
---@param opts dotnet_opts
---@param callback fun(packages: dotnet_packages ): nil called once with the retrieved packages
M.get_installed_packages_parse_csprojs = function(targets, opts, callback)
    local map = {}
    for _, target in ipairs(targets) do
        M.get_installed_packages_parse_csproj(target, opts, function(proj_map)
            for id, entry in pairs(proj_map) do
                if not map[id] then
                    map[id] = { projects = {}, mixed_versions = false }
                end
                table.insert(map[id].projects, entry.projects[1])
            end
        end)
    end
    for _, entry in pairs(map) do
        local first = entry.projects[1] and entry.projects[1].version
        for _, proj in ipairs(entry.projects) do
            if proj.version ~= first then
                entry.mixed_versions = true
                break
            end
        end
        local versions = vim.tbl_map(function(p) return p.version end, entry.projects)
        table.sort(versions, utils.version_lt)
        entry.version = versions[1]
    end
    callback(map)
end

-- Retrieve all the packages used by the given target using `dotnet list`
---@param target string .sln or .csproj file to retrieve packages from. .sln means get packages from all related csprojs.
---@param opts dotnet_opts
---@param callback fun(packages: dotnet_packages): nil called once with the retrieved packages
M.get_installed_packages_dotnet        = function(target, opts, callback)
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
                            map[id] = { projects = {}, mixed_versions = false }
                        end
                        table.insert(map[id].projects, {
                            path    = proj_path,
                            version = pkg.resolvedVersion or pkg.requestedVersion,
                        })
                    end
                end
            end
        end
        for _, entry in pairs(map) do
            local first = entry.projects[1] and entry.projects[1].version
            for _, proj in ipairs(entry.projects) do
                if proj.version ~= first then
                    entry.mixed_versions = true
                    break
                end
            end
            local versions = vim.tbl_map(function(p) return p.version end, entry.projects)
            table.sort(versions, utils.version_lt)
            entry.version = versions[1]
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


---@type dotnet_versions
local version_cache = {}

local function cache_key(id, opts)
    return id:lower() .. (opts.prerelease and ":pre" or "")
end

---Fetch the latest versions of the given package, cached in the module
---@param id string package to fetch
---@param opts dotnet_opts
---@param callback fun(ok: boolean, versions: dotnet_versions?): nil
M.get_latest_versions = function(id, opts, callback)
    local key = cache_key(id, opts)
    local progress = notify.make_progress("get latest " .. key)

    if version_cache[key] then
        progress.finish("found in cache")
        callback(true, version_cache[key])
        return
    end

    local cmd = build_search_command(id, vim.tbl_extend("force", opts, {
        exact_match = true,
        verbosity   = "detailed",
    }))

    progress.report("dotnet search" .. key)
    vim.system(cmd, {}, function(result)
        if result.code ~= 0 then
            progress.finish("failed with exit code " .. tostring(result.code))
            callback(false, nil)
            return
        end
        local ok, decoded = pcall(vim.json.decode, result.stdout or "")
        if not ok or not decoded then
            progress.finish("failed to decode result")
            callback(false, nil)
            return
        end

        ---@type string[]
        local versions = {}
        ---@type string | nil
        local description = nil
        ---@type string | nil
        local project_url = nil
        for _, source in ipairs(decoded.searchResult or {}) do
            for _, pkg in ipairs(source.packages or {}) do
                if pkg.id and pkg.id:lower() == id:lower() then
                    table.insert(versions, pkg.version)
                end
                if pkg.description then
                    description = pkg.description
                end
                if pkg.projectUrl then project_url = pkg.projectUrl end
            end
        end

        if #versions == 0 then
            progress.finish("Found 0 versions")
            callback(false, nil)
            return
        end

        utils.sort_versions(versions, true)
        ---@type dotnet_version
        local entry = {
            latest = versions[1],
            versions = versions,
            description = description,
            project_url = project_url
        }
        version_cache[key] = entry
        progress.finish("Found " .. tostring(#versions) .. " versions")
        callback(true, entry)
    end)
end

M.purge_version_cache = function(id, opts)
    if id then
        version_cache[cache_key(id, opts or {})] = nil
    else
        version_cache = {}
    end
end

---@class dotnet_search_result
---@field id string
---@field version string
---@field downloads number
---@field owners string?
---@field description string?
---@field project_url string?

---Parse output from `dotnet packages search`
---@param json_str string stdout
---@return dotnet_search_result[]
local function parse_package_search_results(json_str)
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

---Search packages with `dotnet package search`
---@param query string search string
---@param opts dotnet_opts
---@param callback fun(ok: boolean, packages: dotnet_search_result?)
M.search_packages = function(query, opts, callback)
    vim.system(build_search_command(query, opts), { cwd = opts.cwd }, function(result)
        if result.code ~= 0 then
            callback(false, nil)
            return
        end
        local packages = parse_package_search_results(result.stdout)
        callback(true, packages)
    end)
end


---Install a package to the given csproj
---@param target string path to .csproj
---@param id string package to install
---@param version string version to install
---@param opts dotnet_opts
---@param callback fun(ok: boolean, stdout: string, stderr: string)
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

---Remove a package from the given csproj
---@param target string path to .csproj
---@param id string package to remove
---@param opts dotnet_opts
---@param callback fun(ok: boolean, stdout: string, stderr: string)
M.remove_package = function(target, id, opts, callback)
    local progress = notify.make_progress("Removing " .. id)

    local cmd      = { opts.dotnet_bin or "dotnet", "remove", target, "package", id }

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
                progress.finish("Removed " .. id)
            else
                progress.cancel("Failed to remove " .. id)
            end
            callback(result.code == 0, result.stdout, result.stderr)
        end)
    end)
end


---finds all csprojs, then returns a list of all of them, and their parent sln, if any
---@param opts dotnet_opts
---@return dotnet_map
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
