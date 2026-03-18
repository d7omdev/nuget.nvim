local entry_display = require("telescope.pickers.entry_display")
local make_entry = require("telescope.make_entry")
local previewers = require("telescope.previewers")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local async_finder = require("nuget.finders.async_finder")
local utils = require("nuget.utils")

local ns_id = vim.api.nvim_create_namespace("NuGetHighlights")

local function build_search_command(query, opts)
    local cmd = { opts.dotnet_bin, "package", "search", query }
    for _, source in ipairs(opts.sources) do
        table.insert(cmd, "--source")
        table.insert(cmd, source)
    end
    if opts.prerelease then
        table.insert(cmd, "--prerelease")
    end
    table.insert(cmd, "--format")
    table.insert(cmd, "json")
    table.insert(cmd, "--verbosity")
    table.insert(cmd, "detailed")
    table.insert(cmd, "--take")
    table.insert(cmd, "10")
    return cmd
end

local function parse_results(json_str)
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

local ns_id = vim.api.nvim_create_namespace("nuget_preview")

local package_previewer = previewers.new_buffer_previewer({
    title = "Package Details",
    get_buffer_by_name = function(_, entry)
        return entry.value.id
    end,
    define_preview = function(self, entry, status)
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

return function(opts)
    opts = vim.tbl_deep_extend("force", {
        sources = {},
        prerelease = false,
        dotnet_bin = "dotnet",
    }, opts or {})

    local displayer = entry_display.create({
        separator = " ",
        items = {
            { width = 50 },
            { remaining = true },
        },
    })

    pickers.new(opts, {
        prompt_title = "NuGet Search",
        finder = async_finder({
            async_fn = function(prompt, on_result, on_complete)
                vim.system(build_search_command(prompt, opts), {}, function(result)
                    if result.code ~= 0 then
                        on_complete()
                        return
                    end
                    local packages = parse_results(result.stdout)
                    for i, pkg in ipairs(packages) do
                        on_result(i, pkg)
                    end
                    on_complete()
                end)
            end,
            entry_maker = function(entry)
                return make_entry.set_default_entry_mt({
                    value = entry,
                    ordinal = entry.id,
                    display = function(et)
                        return displayer({
                            { et.value.id,      "TelescopeResultsIdentifier" },
                            { et.value.version, "TelescopeResultsComment" },
                        })
                    end,
                }, opts)
            end
        }),
        sorter = conf.generic_sorter(opts),
        previewer = package_previewer,
    }):find()
end
