local nuget_pickers = require("nuget.pickers.nuget")
local notify        = require("nuget.notify")
local conf          = require("telescope.config").values
local actions       = require("telescope.actions")
local action_state  = require("telescope.actions.state")
local pickers       = require("telescope.pickers")
local finders       = require("telescope.finders")
local dotnet        = require("nuget.dotnet")
local entry_display = require("telescope.pickers.entry_display")

-- contains pickers for managing nugets on an individual csproj
local M             = {}

---@param csproj_path string The path of the .csproj
M.upgrades          = function(csproj_path, installed, opts)
    nuget_pickers.search({ csproj_path }, installed, opts)
end


---@param csproj_path string The path of the .csproj
---@param installed dotnet_packages
---@param opts { dotnet: dotnet_opts }
M.remove = function(csproj_path, installed, opts)
    local entries = {}
    for id, info in pairs(installed) do
        table.insert(entries, {
            id      = id,
            version = info.version,
        })
    end
    table.sort(entries, function(a, b)
        return a.id < b.id
    end)

    local displayer = entry_display.create({
        separator = " ",
        items     = { { width = 15 }, { remaining = true } },
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
                            { et.value.version, "TelescopeResultsComment" },
                            { et.value.id,      "TelescopeResultsIdentifier" },
                        })
                    end,
                }
            end,
        })
    end

    local picker = pickers.new(opts, {
        prompt_title    = "NuGet Packages | " .. vim.fn.fnamemodify(csproj_path, ":t"),
        finder          = make_finder(),
        sorter          = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                local sel = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if sel then
                    dotnet.remove_package(csproj_path, sel.value.id, opts.dotnet, function(ok, stdout, stderr)
                        if not ok then
                            notify.show_error_float("Failed: " .. sel.value.id .. " " .. sel.value,
                                (stdout or "") .. "\n" .. (stderr or ""))
                            M.remove(csproj_path, installed, opts)
                            return
                        end

                        dotnet.get_installed_packages(csproj_path, opts.dotnet, function(new_installed)
                            vim.schedule(function()
                                M.remove(csproj_path, new_installed, opts)
                            end)
                        end)
                    end)
                end
            end)
            return true
        end,
    })

    picker:find()
end

return M
