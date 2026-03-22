local pickers = require("nuget.pickers")

return function(opts)
    opts = vim.tbl_deep_extend("force", {
        dotnet = {
            sources    = {},
            prerelease = false,
            dotnet_bin = "dotnet",
        }
    }, opts or {})

    opts.filter = "csproj"

    pickers.projects(opts, function(result)
        pickers.csproj.remove(result.path, result.installed, opts)
    end)
end
