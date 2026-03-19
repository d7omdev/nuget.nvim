local entry_display = require("telescope.pickers.entry_display")
local conf          = require("telescope.config").values
local actions       = require("telescope.actions")
local action_state  = require("telescope.actions.state")
local pickers       = require("telescope.pickers")
local finders       = require("telescope.finders")
local dotnet        = require("nuget.dotnet")
local nuget_pickers = require("nuget.pickers.nuget")

local M             = {}

M.upgrades          = function(sln_path, installed, opts)
    local entries = {}
    for id, info in pairs(installed) do
        table.insert(entries, {
            id       = id,
            version  = info.version,
            projects = info.projects,
            outdated = false, -- populated as fetches complete
        })
    end
    table.sort(entries, function(a, b)
        if #a.projects ~= #b.projects then return #a.projects > #b.projects end
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
                        return displayer({
                            { "(" .. #et.value.projects .. ")",       "TelescopeResultsNumber" },
                            { et.value.outdated and "outdated" or "", "DiagnosticWarn" },
                            { et.value.version,                       "TelescopeResultsComment" },
                            { et.value.id,                            "TelescopeResultsIdentifier" },
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
                    nuget_pickers.install(sel.value.projects, sel.value.id, vim.tbl_extend("force", opts, {
                        on_complete = function(ok, new_version)
                            if ok then
                                if installed[sel.value.id] then
                                    installed[sel.value.id].version = new_version
                                end
                            end
                            M.upgrades(sln_path, installed, opts)
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
        dotnet.get_latest_versions(entry.id, opts.dotnet, function(cached)
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
