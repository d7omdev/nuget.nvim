local M = {}
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local utils = require("nuget.utils")

-- Helper function to get installed packages
local function get_installed_packages()
  local project = utils.find_project()

  if not project then
    print("You are not in a .NET project. No .csproj file found.")
    return
  end

  local cmd = string.format("dotnet list %s package", project)
  local output = vim.fn.system(cmd)
  local packages = {}
  for line in output:gmatch("[^\r\n]+") do
    local package = line:match("^%s*> ([^ ]+)")
    if package then
      table.insert(packages, package)
    end
  end
  return packages
end

-- Remove a NuGet package
local function remove_package(package)
  local project = utils.find_project()
  local cmd = string.format("dotnet remove %s package %s", project, package)
  local output = vim.fn.system(cmd)
  if output:match("error") then
    print(string.format("Failed to remove package %s: %s", package, output))
  else
    local restore_cmd = string.format("dotnet restore %s", project)
    local restore_output = vim.fn.system(restore_cmd)
    if restore_output:match("error") then
      print(string.format("Failed to restore project %s: %s", project, restore_output))
    else
      print(string.format("Removed package %s", package))
    end
  end
end

-- List and remove NuGet packages
function M.remove_package()
  local packages = get_installed_packages()

  if packages == nil then
    return
  end

  if #packages == 0 then
    print("No packages found in the project")
    return
  end

  local function enter(prompt_bufnr)
    local selected = action_state.get_selected_entry()
    if selected then
      actions.close(prompt_bufnr)
      remove_package(selected.value)
    else
      print("No package selected")
    end
  end

  pickers
    .new({}, {
      prompt_title = "Remove NuGet Package",
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
      sorter = conf.generic_sorter({}),
      attach_mappings = function(_, map)
        map("i", "<CR>", enter)
        return true
      end,
      layout_config = {
        preview_width = 0.7,
        width = 0.5,
      },
    })
    :find()
end

return M
