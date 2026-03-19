local pickers = require("nuget.pickers")

return function(opts)
    opts = vim.tbl_deep_extend("force", {
        dotnet = {
            sources    = {},
            prerelease = false,
            dotnet_bin = "dotnet",
        }
    }, opts or {})

    pickers.projects(opts, function(result)
        if result.filetype == "sln" then
            pickers.sln.upgrades(result.path, result.installed, opts)
        else
            vim.notify('picked csproj')
        end
    end)
end
