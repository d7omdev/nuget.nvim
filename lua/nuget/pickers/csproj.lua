local nuget_pickers = require("nuget.pickers.nuget")

-- contains pickers for managing nugets on an individual csproj
local M = {}

---@param csproj_path string The path of the .csproj
M.upgrades = function(csproj_path, installed, opts)
    nuget_pickers.search({ csproj_path }, installed, opts)
end

return M
