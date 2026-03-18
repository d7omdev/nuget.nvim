local entry_display = require('telescope.pickers.entry_display')
local utils = require('telescope.utils')
local builtin = require('telescope.builtin')

-- find csproj and sln files
return function(opts)
    opts = opts or {}
    opts.find_command = opts.find_command or
        { "fd", "--type", "f", "--color", "never", "-e", "csproj", "-e", "sln", "--exclude", ".git", "-L" }

    opts.entry_maker = function(line)
        local fn = utils.path_tail(line)
        local path = string.sub(line, 1, -(#fn + 1))

        local ord = opts.search_directory and line or fn
        local entry = {
            ordinal = ord,
            __fn = fn,
            __path = path,
            path = line
        }

        local displayer = entry_display.create({
            separator = "",
            items = {
                { width = nil },
                { width = nil },
            }
        })

        entry.display = function(et)
            return displayer({
                { et.__path, "TelescopeResultsComment" },
                { et.__fn }
            })
        end
        return entry;
    end

    return builtin.find_files(opts)
end
