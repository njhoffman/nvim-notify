local parse_highlights = require("notify.parser.highlights")
local capture = require("notify.parser.capture")

-- handles tables in notification message that either contain body highlights or objects to inspect
-- returns plain string and table of lines each containing arrays of { Content, HLName? }
-- todo: better version of this where it scans table and ensures never more than two elements
local config_formatter = function(default_config)
  local lines = { "Default values:", ">lua" }
  for line in vim.gsplit(vim.inspect(default_config), "\n", true) do
    table.insert(lines, "  " .. line)
  end
  table.insert(lines, "<")
  return lines
end

-- extract embedded objects or highlights, return parsed options and clean string
local default_formatter = function(msg, level, opts)
  if type(msg) == "table" then
    if vim.islist(msg) then
      return vim.fn.join(msg, "\n"), level, opts
    else
      return vim.inspect(msg), level, opts
    end
  end
  return msg, level, opts
end

local parse_captures = function(message, level, opts)
  return message or "", level, opts
end

local parse_message = function(message, level, opts)
  opts = opts or {}
  if type(message) == "table" then
    return parse_highlights(message, level, opts)
  end

  return parse_captures(message, level, opts)
end

return {
  default_captures = capture.defaults,
  default_formatter = default_formatter,
  config_formatter = config_formatter,
  parse_message = parse_message,
}
