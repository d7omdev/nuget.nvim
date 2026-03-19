local entry_display = require("telescope.pickers.entry_display")
local conf          = require("telescope.config").values
local actions       = require("telescope.actions")
local action_state  = require("telescope.actions.state")
local pickers       = require("telescope.pickers")
local finders       = require("telescope.finders")
local dotnet        = require("nuget.dotnet")
local nuget_pickers = require("nuget.pickers.nuget")

local M             = {}

---Launch picker to upgrade all packages in a given .sln
---@param sln_path string path to .sln file
---@param installed dotnet_packages already installed packages
---@param opts { dotnet: dotnet_opts }
M.upgrades          = function(sln_path, installed, opts)
    local entries = {}
    for id, info in pairs(installed) do
        table.insert(entries, {
            id       = id,
            version  = info.version,
            projects = info.projects,
            outdated = false, -- populated as fetches complete
            mixed    = info.mixed_versions,
        })
    end
    table.sort(entries, function(a, b)
        return a.id < b.id
    end)

    local displayer = entry_display.create({
        separator = " ",
        items     = { { width = 5 }, { width = 8 }, { width = 15 }, { remaining = true } },
    })

    local function make_finder()
        return finders.new_table({
            results     = entries,
            entry_maker = function(e)
                return {
                    value   = e,
                    ordinal = e.id,
                    display = function(et)
                        local flag, flag_hl = "", "DiagnosticWarn"
                        if et.value.mixed then
                            flag, flag_hl = "mixed", "DiagnosticError"
                        elseif et.value.outdated then
                            flag = "outdated"
                        end
                        return displayer({
                            { "(" .. #et.value.projects .. ")", "DiagnosticHint" },
                            { flag,                             flag_hl },
                            { et.value.version,                 "TelescopeResultsComment" },
                            { et.value.id,                      "TelescopeResultsIdentifier" },
                        })
                    end,
                }
            end,
        })
    end

    local picker = pickers.new(opts, {
        prompt_title    = "Solution Packages | " .. vim.fn.fnamemodify(sln_path, ":t"),
        finder          = make_finder(),
        sorter          = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                local sel = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if sel then
                    nuget_pickers.install(vim.tbl_map(function(p) return p.path end, sel.value.projects), sel.value.id,
                        vim.tbl_extend("force", opts, {
                            on_complete = function(ok, _)
                                if not ok then
                                    M.upgrades(sln_path, installed, opts)
                                    return
                                end
                                -- regenerate the project map to account for changes in the installed packages
                                dotnet.get_installed_packages(sln_path, opts.dotnet, nil, function(new_installed)
                                    vim.schedule(function()
                                        M.upgrades(sln_path, new_installed, opts)
                                    end)
                                end)
                            end
                        }))
                end
            end)
            return true
        end,
    })

    picker:find()

    -- kick off all fetches immediately after picker opens
    for _, entry in ipairs(entries) do
        dotnet.get_latest_versions(entry.id, opts.dotnet, function(ok, cached)
            if not ok then
                return
            end
            if cached.latest ~= entry.version then
                vim.schedule(function()
                    entry.outdated = true
                    picker:refresh(make_finder(), { reset_prompt = false })
                end)
            end
        end)
    end
end

return M
