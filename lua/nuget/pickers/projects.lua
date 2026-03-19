local entry_display   = require('telescope.pickers.entry_display')
local telescope_utils = require('telescope.utils')
local builtin         = require('telescope.builtin')
local actions         = require("telescope.actions")
local action_state    = require("telescope.actions.state")
local notify          = require("nuget.notify")
local dotnet          = require("nuget.dotnet")

--- Open a project/solution file picker.
---
--- opts
---   .find_command   override fd command
---   .filter         "csproj" | "sln" | nil (show both)
---   .prompt_title   override default title
---   .dotnet         additional settings to pass to nuget.dotnet commands
---
--- callback({ path, filetype, installed, opts })
---   Called on the main loop after the user picks a file and installed packages
---   have been fetched.  `installed` is the map from dotnet.get_installed_packages.
return function(opts, callback)
    opts = opts or {}

    local get_command = function()
        if opts.filter == "sln" then
            return { "fd", "--type", "f", "--color", "never", "-e", "sln", "--exclude", ".git", "-L" }
        elseif opts.filter == "csproj" then
            return { "fd", "--type", "f", "--color", "never", "-e", "csproj", "--exclude", ".git", "-L" }
        end
        return { "fd", "--type", "f", "--color", "never", "-e", "csproj", "-e", "sln", "--exclude", ".git", "-L" }
    end
    opts.find_command = opts.find_command or get_command()

    local displayer = entry_display.create({
        separator = "",
        items = {
            { width = nil },
            { width = nil },
        }
    })

    local proj_opts = vim.tbl_extend("force", opts, {
        prompt_title = opts.prompt_title or "Select Project / Solution",

        entry_maker = function(line)
            local fn       = telescope_utils.path_tail(line)
            local path     = string.sub(line, 1, -(#fn + 1))
            local filetype = fn:match("^.+%.(%w+)$")
            local entry    = {
                ordinal  = fn,
                __fn     = fn,
                __path   = path,
                path     = line,
                filetype = filetype,
            }
            entry.display  = function(et)
                return displayer({
                    { et.__path, "TelescopeResultsComment" },
                    { et.__fn, et.is_sln and "TelescopeResultsSpecialComment"
                    or "TelescopeResultsNormal" },
                })
            end
            return entry
        end,

        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                local sel = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if not sel then return end

                local progress = notify.make_progress("Loading installed packages…")
                dotnet.get_installed_packages(sel.path, opts.dotnet, function(installed)
                    vim.schedule(function()
                        progress.finish(vim.tbl_count(installed) .. " packages indexed")
                        callback({ path = sel.path, filetype = sel.filetype, installed = installed, opts = opts })
                    end)
                end)
            end)
            return true
        end,
    })

    -- opts.entry_maker = function(line)
    --     local fn = utils.path_tail(line)
    --     local path = string.sub(line, 1, -(#fn + 1))
    --
    --     local ord = opts.search_directory and line or fn
    --     local entry = {
    --         ordinal = ord,
    --         __fn = fn,
    --         __path = path,
    --         path = line
    --     }
    --
    --
    --     entry.display = function(et)
    --         return displayer({
    --             { et.__path, "TelescopeResultsComment" },
    --             { et.__fn }
    --         })
    --     end
    --     return entry;
    -- end

    return builtin.find_files(proj_opts)
end
