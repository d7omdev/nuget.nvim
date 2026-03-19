local M = {}

local fidget_ok, fidget = pcall(require, "fidget")
local progress_ok, fidget_progress = pcall(require, "fidget.progress")

--- Create a fidget progress handle, falling back to vim.notify if unavailable.
--- Returns a handle with :report(msg) and :finish(msg) methods.
M.make_progress = function(title)
    if progress_ok then
        local handle = fidget_progress.handle.create({
            title = title,
            lsp_client = { name = "nuget" },
            percentage = nil,
        })
        return {
            report = function(msg) handle:report({ message = msg }) end,
            finish = function(msg)
                handle:report({ message = msg or "Done" })
                handle:finish()
            end,
            cancel = function(msg)
                handle:report({ message = msg or "Cancelled" })
                handle:finish()
            end,
        }
    else
        -- Minimal fallback
        return {
            report = function(msg) vim.schedule(function() vim.notify("[nuget] " .. msg, vim.log.levels.INFO) end) end,
            finish = function(msg) vim.schedule(function() vim.notify("[nuget] " .. (msg or "Done"), vim.log.levels.INFO) end) end,
            cancel = function(msg)
                vim.schedule(function()
                    vim.notify("[nuget] " .. (msg or "Cancelled"),
                        vim.log.levels.WARN)
                end)
            end,
        }
    end
end

--- Show failure output in a floating scratch buffer the user can read and close.
M.show_error_float = function(title, output)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "text"

    local lines = vim.split(output or "(no output)", "\n", { plain = true })
    table.insert(lines, 1, title)
    table.insert(lines, 2, string.rep("─", math.min(80, vim.o.columns - 4)))
    table.insert(lines, "")
    table.insert(lines, "[press q or <Esc> to close]")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local width = math.min(100, vim.o.columns - 4)
    local height = math.min(#lines + 2, vim.o.lines - 6)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        style = "minimal",
        border = "rounded",
        title = " NuGet Error ",
        title_pos = "center",
    })
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    -- Close keymaps
    for _, key in ipairs({ "q", "<Esc>" }) do
        vim.keymap.set("n", key, function()
            vim.api.nvim_win_close(win, true)
        end, { buffer = buf, nowait = true, silent = true })
    end
end

M.show_info_float = function(title, message)
    local buf             = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype   = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype  = "text"
    local lines           = vim.split(message, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local width      = math.min(60, vim.o.columns - 4)
    local height     = #lines
    local win        = vim.api.nvim_open_win(buf, false, {
        relative  = "editor",
        width     = width,
        height    = height,
        row       = math.floor((vim.o.lines - height) / 2),
        col       = math.floor((vim.o.columns - width) / 2),
        style     = "minimal",
        border    = "rounded",
        title     = " " .. title .. " ",
        title_pos = "center",
    })
    vim.wo[win].wrap = true
    return function()
        vim.schedule(function()
            if vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_close(win, true)
            end
        end)
    end
end

return M
