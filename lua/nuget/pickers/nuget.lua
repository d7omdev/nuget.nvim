local entry_display = require("telescope.pickers.entry_display")
local make_entry    = require("telescope.make_entry")
local previewers    = require("telescope.previewers")
local pickers       = require("telescope.pickers")
local conf          = require("telescope.config").values
local async_finder  = require("nuget.finders.async_finder")
local utils         = require("nuget.utils")
local dotnet        = require("nuget.dotnet")
local notify        = require("nuget.notify")
local finders       = require("telescope.finders")
local actions       = require("telescope.actions")
local action_state  = require("telescope.actions.state")

local M             = {}

local ns_id         = vim.api.nvim_create_namespace("NuGetHighlights")

M.package_previewer = previewers.new_buffer_previewer({
    title = "Package Details",
    get_buffer_by_name = function(_, entry)
        return entry.value.id
    end,
    define_preview = function(self, entry, _)
        local pkg = entry.value

        local function val(v)
            if type(v) == "table" then
                return table.concat(v, ", ")
            elseif v == nil or v == "" then
                return "N/A"
            else
                return tostring(v):gsub("\r\n", "\n"):gsub("\r", "\n")
            end
        end

        local lines = {}
        local highlights = {}

        table.insert(lines, pkg.id .. " " .. val(pkg.version))
        table.insert(highlights, { line = 0, hl = "Title", col_start = 0, col_end = #pkg.id })
        table.insert(highlights, { line = 0, hl = "TelescopeResultsNormal", col_start = #pkg.id + 1, col_end = -1 })

        if pkg.owners and pkg.owners ~= "" then
            table.insert(highlights, { line = #lines, hl = "TelescopeResultsComment" })
            table.insert(lines, "by " .. val(pkg.owners))
        end

        table.insert(lines, "")

        local fields = {
            { label = "Project URL",     value = pkg.project_url },
            { label = "Total Downloads", value = pkg.downloads and utils.humanize(pkg.downloads) or nil },
        }
        for _, field in ipairs(fields) do
            local v = val(field.value)
            if v ~= "N/A" then
                local line = field.label .. ": " .. v
                table.insert(highlights, { line = #lines, hl = "Title", col_start = 0, col_end = #field.label })
                table.insert(lines, line)
            end
        end

        table.insert(lines, "")

        if pkg.description and pkg.description ~= "" then
            for _, vline in ipairs(vim.split(val(pkg.description), "\n", { plain = true })) do
                table.insert(lines, vline)
            end
        end


        vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(self.state.bufnr) then return end
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
            -- enable soft wrap instead of manual wrapping
            vim.wo[self.state.winid].wrap = true
            vim.wo[self.state.winid].linebreak = true
            for _, h in ipairs(highlights) do
                vim.api.nvim_buf_add_highlight(self.state.bufnr, ns_id, h.hl, h.line, h.col_start or 0, h.col_end or -1)
            end
        end)
    end,
})

---Search for a nuget and install it on the given csprojs
---@param targets string[] List of csprojs to install selected package to
---@param installed dotnet_packages
---@param opts { dotnet: dotnet_opts }
M.search            = function(targets, installed, opts)
    opts = vim.tbl_deep_extend("force", {
        dotnet = {}
    }, opts or {})

    local displayer = entry_display.create({
        separator = " ",
        items     = { { width = 8 }, { width = 15 }, { remaining = true } },
    })

    local existing_entries = {}
    local keyed_existing_entries = {}
    for id, info in pairs(installed) do
        local entry = {
            id       = id,
            version  = info.version,
            outdated = false, -- populated as fetches complete
        }
        table.insert(existing_entries, entry)
        keyed_existing_entries[entry.id] = entry
    end

    local function make_finder()
        return async_finder({
            initial_results = existing_entries,
            async_fn = function(prompt, on_result, on_complete)
                dotnet.search_packages(prompt, opts.dotnet, function(ok, result)
                    if not ok then
                        on_complete()
                        return
                    end
                    for i, pkg in ipairs(result) do
                        on_result(i, pkg)
                    end
                    on_complete()
                end)
            end,
            entry_maker = function(entry)
                entry = keyed_existing_entries[entry.id] or entry
                local flag = entry.outdated and "outdated" or ""
                return make_entry.set_default_entry_mt({
                    value = entry,
                    ordinal = entry.id .. flag,
                    display = function(et)
                        return displayer({
                            { flag,             "DiagnosticWarn" },
                            { et.value.version, "TelescopeResultsComment" },
                            { et.value.id,      "TelescopeResultsIdentifier" },
                        })
                    end,
                }, opts)
            end
        })
    end


    local picker = pickers.new(opts, {
        prompt_title = "NuGet Search",
        finder = make_finder(),
        sorter = conf.generic_sorter(opts),
        previewer = M.package_previewer,
        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                local sel = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if sel then
                    M.install(targets, sel.value.id, vim.tbl_extend("force", opts, {
                        on_complete = function(ok, _)
                            if ok then
                                dotnet.get_installed_packages_parse_csprojs(targets, opts.dotnet,
                                    function(updated_installed)
                                        M.search(targets, updated_installed, opts)
                                    end)
                            else
                                M.search(targets, installed, opts)
                            end
                        end
                    }))
                end
            end)
            return true
        end,
    })
    picker:find()

    -- kick off all fetches immediately after picker opens
    for _, entry in ipairs(existing_entries) do
        dotnet.get_latest_versions(entry.id, opts.dotnet, function(ok, cached)
            if not ok then
                return
            end
            entry.description = cached.description
            entry.project_url = cached.project_url
            if cached.latest ~= entry.version then
                vim.schedule(function()
                    entry.outdated = true
                    picker:refresh(make_finder(), { reset_prompt = false })
                end)
            end
        end)
    end
end

---Create a picker to select the version of a given nuget and install it on the given csprojs
---@param targets string[] List of csprojs to install selected package to
---@param package string package to install
---@param opts { dotnet: dotnet_opts, on_complete: fun(ok: boolean, new_version: string?) }
M.install           = function(targets, package, opts)
    local progress = notify.make_progress("NuGet search " .. package)

    -- generate a list of siblings that share the same sln (if any) with any of
    -- the targets, including targets themselves
    progress.report("Building project map")
    local project_map = dotnet.build_project_map(opts.dotnet)
    local slns = {}
    local csprojs_for_counts = {}
    for _, target in ipairs(targets) do
        local entry = project_map[target]
        if entry.sln then
            slns[entry.sln] = true
        end
        csprojs_for_counts[target] = true
    end
    for csproj, info in pairs(project_map) do
        if info.sln and slns[info.sln] then
            csprojs_for_counts[csproj] = true
        end
    end

    -- build version→projects map from siblings
    local version_projects = {}
    local pending = vim.tbl_count(csprojs_for_counts)
    local function on_siblings_done()
        progress.report("Querying NuGet")
        dotnet.get_latest_versions(package, opts.dotnet, function(ok, result)
            if not ok then
                progress.finish("Found 0 versions")
                vim.schedule(function()
                    notify.show_error_float("NuGet", "Couldn't find any versions for NuGet " .. package, function()
                        if opts.on_complete then opts.on_complete(false, nil) end
                    end)
                end)
                return
            end
            vim.schedule(function()
                progress.finish("Found " .. tostring(#result.versions) .. " versions")

                local displayer = entry_display.create({
                    separator = " ",
                    items     = { { width = 20 }, { remaining = true } },
                })

                local entries = {}
                for _, v in ipairs(result.versions) do
                    -- basically we want current, latest, used in other csprojs, everything else
                    local projs     = version_projects[v] or {}
                    local other_cnt = #projs
                    local is_cur    = false
                    for _, proj in ipairs(projs) do
                        if vim.tbl_contains(targets, proj) then
                            is_cur = true
                        else
                            other_cnt = other_cnt + 1
                        end
                    end
                    local is_latest = v == result.versions[1]
                    local prefix
                    if is_cur then
                        prefix = "3_"
                    elseif is_latest then
                        prefix = "2_"
                    elseif other_cnt > 0 then
                        prefix = "1_"
                    else
                        prefix = "0_"
                    end
                    local ordinal = prefix .. utils.version_ordinal(v)
                    table.insert(entries, {
                        value     = v,
                        ordinal   = ordinal,
                        is_cur    = is_cur,
                        other_cnt = other_cnt,
                        is_latest = is_latest,
                        display   = function(et)
                            local badge, badge_hl
                            if et.is_cur then
                                badge, badge_hl = "current", "DiagnosticOk"
                            elseif et.is_latest then
                                badge, badge_hl = "latest", "DiagnosticInfo"
                            elseif et.other_cnt > 0 then
                                badge, badge_hl = "(" .. tostring(et.other_cnt) .. ")", "DiagnosticHint"
                            else
                                badge, badge_hl = "", "TelescopeResultsComment"
                            end
                            return displayer({
                                { et.value, et.is_cur and "DiagnosticOk" or "TelescopeResultsNormal" },
                                { badge,    badge_hl },
                            })
                        end,
                    })
                end

                -- for the initial (unsorted) view
                table.sort(entries, function(a, b) return a.ordinal > b.ordinal end)

                pickers.new({}, {
                    initial_mode    = "normal",
                    prompt_title    = "Select Version | " .. package,
                    finder          = finders.new_table({
                        results     = entries,
                        entry_maker = function(e) return e end,
                    }),
                    sorter          = conf.generic_sorter({}),
                    attach_mappings = function(prompt_bufnr, _)
                        local selected = false
                        vim.api.nvim_create_autocmd("BufUnload", {
                            buffer   = prompt_bufnr,
                            once     = true,
                            callback = function()
                                vim.schedule(function()
                                    if not selected then
                                        if opts.on_complete then opts.on_complete(false, nil) end
                                    end
                                end)
                            end,
                        })


                        actions.select_default:replace(function()
                            local sel = action_state.get_selected_entry()
                            actions.close(prompt_bufnr)
                            if not sel then
                                return
                            end
                            local close            = notify.show_info_float("NuGet", "Installing " ..
                                package .. "\nVersion " .. sel.value .. "...")
                            selected               = true
                            local pending_installs = #targets
                            local all_ok           = true
                            for _, target in ipairs(targets) do
                                dotnet.install_package(target, package, sel.value, opts,
                                    function(install_ok, stdout, stderr)
                                        if not install_ok then
                                            all_ok = false
                                            notify.show_error_float("Failed: " .. package .. " " .. sel.value,
                                                (stdout or "") .. "\n" .. (stderr or ""))
                                        end
                                        pending_installs = pending_installs - 1
                                        if pending_installs == 0 then
                                            close()
                                            if opts.on_complete then opts.on_complete(all_ok, sel.value) end
                                        end
                                    end)
                            end
                        end)
                        return true
                    end,
                }):find()
            end)
        end)
    end

    if pending == 0 then
        on_siblings_done()
        return
    end

    for csproj, _ in pairs(csprojs_for_counts) do
        dotnet.get_installed_packages_parse_csproj(csproj, opts.dotnet,
            function(map)
                local info = map[package]
                if info and info.version then
                    version_projects[info.version] = version_projects[info.version] or {}
                    table.insert(version_projects[info.version], csproj)
                end
                pending = pending - 1
                if pending == 0 then on_siblings_done() end
            end)
    end
end

return M
