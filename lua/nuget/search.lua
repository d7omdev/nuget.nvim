local search = {}
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")
local utils = require("nuget.utils")
local install = require("nuget.install")

local ns_id = vim.api.nvim_create_namespace("NuGetHighlights")
--
-- Package details previewer
local package_previewer = previewers.new_buffer_previewer({
	title = "Package Details",
	get_buffer_by_name = function(_, entry)
		return entry.value
	end,
	define_preview = function(self, entry, status)
		local url = string.format("https://api-v2v3search-0.nuget.org/query?q=%s", entry.value)
		local response = utils.http_get(url)
		if response and response.data and response.data[1] then
			local pkg = response.data[1]
			local function safe_concat(value)
				if type(value) == "table" then
					return table.concat(value, ", ")
				elseif value == nil then
					return "N/A"
				else
					return tostring(value):gsub("\n", " "):gsub("\r", "")
				end
			end
			local lines = {
				"Package: ",
				"  " .. safe_concat(pkg.id),
				"  ",
				"Version: ",
				"  " .. safe_concat(pkg.version),
				"  ",
				"Description: ",
				"  " .. safe_concat(pkg.description),
				"  ",
				"Authors: ",
				"  " .. safe_concat(pkg.authors),
				"  ",
				"Project URL: ",
				"  " .. safe_concat(pkg.projectUrl),
				"  ",
				"License: ",
				"  " .. safe_concat(pkg.licenseUrl),
				"  ",
				"Total Downloads: ",
				"  " .. safe_concat(pkg.totalDownloads),
				"",
			}
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(self.state.bufnr) then
					-- Manually wrap text
					local max_width = vim.api.nvim_win_get_width(0)
					local wrapped_lines = {}
					for _, line in ipairs(lines) do
						local words = {}
						for word in line:gmatch("%S+") do
							table.insert(words, word)
						end
						if #words > 0 then
							local current_line = table.remove(words, 1)
							for _, word in ipairs(words) do
								if #word > max_width then
									table.insert(wrapped_lines, current_line)
									table.insert(wrapped_lines, word)
									current_line = ""
								elseif #current_line + #word + 1 > max_width then
									table.insert(wrapped_lines, current_line)
									current_line = word
								else
									current_line = current_line .. " " .. word
								end
							end
							if #current_line > 0 then
								table.insert(wrapped_lines, current_line)
							end
						end
					end

					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, wrapped_lines)
					-- Add highlights
					for i, line in ipairs(wrapped_lines) do
						if line:match("^.*:$") then
							-- Make the title bolder
							vim.api.nvim_buf_add_highlight(self.state.bufnr, ns_id, "Title", i - 1, 0, -1)
						elseif i == 2 then
							-- Make the package name yellow
							vim.api.nvim_buf_add_highlight(self.state.bufnr, ns_id, "WarningMsg", i - 1, 0, -1)
						end
					end
				end
			end)
		else
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(self.state.bufnr) then
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "No details available" })
				end
			end)
		end
	end,
})

-- Search for NuGet packages
function search.search_packages()
	local project = utils.find_project()

	if not project then
		print("You are not in a .NET project. No .csproj file found.")
		return
	end

	local query = vim.fn.input("Enter search term: ")
	local function enter(prompt_bufnr)
		local selected = action_state.get_selected_entry()
		if selected then
			actions.close(prompt_bufnr)
			search.package_versions(selected.value)
		else
			print("No package selected")
		end
	end
	local url = string.format("https://api-v2v3search-0.nuget.org/query?q=%s&take=200&includeDelisted=false", query)
	local response = utils.http_get(url)
	local packages = {}
	for _, pkg in ipairs(response.data) do
		table.insert(packages, pkg.id)
	end
	pickers
		.new({}, {
			prompt_title = "Search NuGet Packages",
			finder = finders.new_table({
				results = packages,
				entry_maker = function(pkg)
					return {
						value = pkg,
						display = pkg,
						ordinal = pkg,
					}
				end,
			}),
			layout_config = {
				preview_width = 0.60,
			},
			sorter = conf.generic_sorter({}),
			previewer = package_previewer,
			attach_mappings = function(_, map)
				map("i", "<CR>", enter)
				return true
			end,
		})
		:find()
end

-- Show package versions
function search.package_versions(package)
	local function enter(prompt_bufnr)
		local selected = action_state.get_selected_entry()
		if selected then
			actions.close(prompt_bufnr)
			install.install_package(package)
		else
			print("No version selected")
		end
	end
	local url = string.format("https://api.nuget.org/v3-flatcontainer/%s/index.json", package)
	local response = utils.http_get(url)
	local versions = response.versions
	table.sort(versions, function(a, b)
		return a > b
	end)
	pickers
		.new({}, {
			prompt_title = string.format("Versions for %s", package),
			finder = finders.new_table({
				results = versions,
				entry_maker = function(version)
					return {
						value = version,
						display = version,
						ordinal = version,
					}
				end,
			}),
			layout_config = { width = 0.40 },
			sorter = conf.generic_sorter({}),
			attach_mappings = function(_, map)
				map("i", "<CR>", enter)
				return true
			end,
		})
		:find()
end

return search
