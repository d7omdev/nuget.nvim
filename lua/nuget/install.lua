local install = {}
local utils = require("nuget.utils")

function install.install_package(package)
	local project_file = utils.find_project()

	if not project_file then
		print("You are not in a .NET project. No .csproj file found.")
		return
	end

	local cmd = string.format("dotnet add %s package %s", project_file, package)

	-- Run the command and capture its output
	local output = vim.fn.system(cmd)

	-- Split the output into lines
	local lines = {}
	for line in output:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	-- Create a floating window
	local bufnr = vim.api.nvim_create_buf(false, true)
	local win_width = math.min(80, vim.api.nvim_get_option("columns"))
	local win_height = math.min(30, vim.api.nvim_get_option("lines"))
	local win_opts = {
		relative = "editor",
		width = win_width,
		height = win_height,
		row = (vim.api.nvim_get_option("lines") - win_height) / 2,
		col = (vim.api.nvim_get_option("columns") - win_width) / 2,
		style = "minimal",
	}
	vim.api.nvim_open_win(bufnr, true, win_opts)

	-- Set the buffer's contents to the output lines
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

	-- Close the floating window when the command finishes
	vim.fn.jobstart(cmd, {
		on_exit = function(j, return_val, event)
			if return_val == 0 then
				print("Installed Package " .. package)
			else
				print("Failed to install package " .. package)
			end
			vim.api.nvim_win_close(0, true)
		end,
	})

	-- Check if the package is already installed
	if output:match("already installed") then
		print("Package " .. package .. " is already installed")
	end
end

return install
