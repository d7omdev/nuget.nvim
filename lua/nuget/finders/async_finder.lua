-- based off https://gist.github.com/chuwy/e8476156d6dd4815611228dc96196554
local make_entry = require("telescope.make_entry")

return function(opts)
    local entry_maker = opts.entry_maker or make_entry.gen_from_string(opts)
    local debounce_ms = opts.debounce_ms or 500
    local timer = nil
    local cancelled = false
    local generation = 0 -- increments on each new search

    local function debounce(thunk)
        if timer ~= nil then timer:stop() end
        timer = vim.uv.new_timer()
        timer:start(debounce_ms, 0, function()
            thunk()
            timer:stop()
        end)
    end

    local callable = function(_, prompt, process_result, process_complete)
        if not prompt or prompt == "" then
            if opts.initial_results then
                for i, item in ipairs(opts.initial_results) do
                    local entry = entry_maker(item)
                    if entry then
                        entry.index = i
                        process_result(entry)
                    end
                end
            end
            process_complete()
            return
        end
        generation = generation + 1
        local my_generation = generation
        debounce(function()
            opts.async_fn(prompt, function(i, item)
                if cancelled or generation ~= my_generation then return end
                local entry = entry_maker(item)
                if entry then
                    entry.index = i
                    vim.schedule(function()
                        if generation ~= my_generation then return end
                        process_result(entry)
                    end)
                end
            end, function()
                if cancelled or generation ~= my_generation then return end
                vim.schedule(process_complete)
            end)
        end)
    end

    return setmetatable({
        close = function()
            cancelled = true
            if timer ~= nil then
                timer:stop()
                timer = nil
            end
        end,
    }, { __call = callable })
end
