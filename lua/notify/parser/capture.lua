local default_captures = {
  ---@type table<string, function|table>
  ["|(%S-)|"] = { "vim_link", cmd = vim.cmd.help },
  ["%[.-%]%((file:%S-)%)"] = {
    "file_loc",
    cmd = require("noice.util").openHoverFile,
    priority = 10,
  },
  ["%[.-%]%((%S-)%)"] = { "md_link", cmd = require("noice.util").open },
}

local process_captures = function() end

return { defaults = default_captures, process = process_captures }
