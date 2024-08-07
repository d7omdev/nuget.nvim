local utils = {}

-- Helper function to make HTTP requests
function utils.http_get(url)
	local curl = require("plenary.curl")
	local response = curl.get(url)
	return vim.fn.json_decode(response.body)
end

-- Find the nearest .csproj file
function utils.find_project()
	local file = vim.fn.expand("%:p")
	local dir = vim.fn.fnamemodify(file, ":h")
	while dir ~= "/" do
		local files = vim.fn.glob(dir .. "/*.csproj", false, true)
		if #files > 0 then
			return files[1]
		end
		dir = vim.fn.fnamemodify(dir, ":h")
	end
	return nil
end

return utils
