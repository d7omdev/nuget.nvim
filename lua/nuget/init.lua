local nuget = {}

-- Load functionalities
local remove = require("nuget.remove")
local install = require("nuget.install")
local dotnet = require("nuget.dotnet")

-- Default keymaps
local default_keys = {
    install = { "n", "<leader>ni" },
    remove = { "n", "<leader>nr" },
    clear_cache = { "n", "<leader>nc" },
}

-- Set the commands to ensure they are always available
vim.api.nvim_create_user_command("NuGetInstall", function()
    install()
end, {})

vim.api.nvim_create_user_command("NuGetRemove", function()
    remove()
end, {})

vim.api.nvim_create_user_command("NuGetClearCache", function()
    dotnet.purge_version_cache()
    vim.notify("nuget.nvim cache cleared!")
end, {})

-- Function to setup keymaps
function nuget.setup(opts)
    opts = opts or {}

    -- If no keys are provided, use default keymaps
    if opts.keys == nil then
        opts.keys = default_keys
    end

    -- Disable keymaps if an empty keys table is provided
    if next(opts.keys) == nil then
        vim.api.nvim_del_keymap("n", default_keys.install[2])
        vim.api.nvim_del_keymap("n", default_keys.remove[2])
        vim.api.nvim_del_keymap("n", default_keys.clear_cache[2])
    else
        -- Set provided keymaps or default keymaps
        if opts.keys.install then
            vim.api.nvim_set_keymap(
                opts.keys.install[1],
                opts.keys.install[2],
                "<cmd>NuGetInstall<CR>",
                { noremap = true, silent = true, desc = "Install a NuGet package" }
            )
        end

        if opts.keys.remove then
            vim.api.nvim_set_keymap(
                opts.keys.remove[1],
                opts.keys.remove[2],
                "<cmd>NuGetRemove<CR>",
                { noremap = true, silent = true, desc = "Remove a NuGet package" }
            )
        end

        if opts.keys.clear_cache then
            vim.api.nvim_set_keymap(
                opts.keys.clear_cache[1],
                opts.keys.clear_cache[2],
                "<cmd>NuGetClearCache<CR>",
                { noremap = true, silent = true, desc = "Clear nuget.nvim cache" }
            )
        end
    end
end

return nuget
