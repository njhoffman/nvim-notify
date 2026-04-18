local parse_highlights = require("notify.parsers.highlights")
local capture = require("notify.parsers.capture")
local compat = require("notify.compat")
local registry = require("notify.parsers.registry")

--- Pretty-print the default config as vim help lines.
local config_formatter = function(default_config)
  local lines = { "Default values:", ">lua" }
  for line in vim.gsplit(vim.inspect(default_config), "\n", true) do
    table.insert(lines, "  " .. line)
  end
  table.insert(lines, "<")
  return lines
end

--- Coerce a table-shaped `message` into a string, inspecting dict-like
--- inputs. Highlight-bearing tables go through `parsers.highlights` which
--- writes `opts.highlights.inline`.
local default_formatter = function(msg, level, opts)
  if type(msg) == "table" then
    if compat.islist(msg) then
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

--- Primary entry point. Runs the legacy table-message coercion and the
--- decorator/matcher registry. `opts.parser = false` bypasses everything.
local parse_message = function(message, level, opts, config)
  opts = opts or {}
  if type(message) == "table" then
    local msg, parsed_opts = parse_highlights(message, opts)
    message, opts = msg, parsed_opts
  elseif message == nil then
    message = ""
  end
  return registry.run(message, level, opts, config)
end

-- Auto-register built-in decorators.
require("notify.parsers.decorators.lines").register(registry)

return {
  default_captures = capture.defaults,
  default_formatter = default_formatter,
  config_formatter = config_formatter,
  parse_message = parse_message,

  register_decorator = registry.register_decorator,
  unregister_decorator = registry.unregister_decorator,
  register_matcher = registry.register_matcher,
  unregister_matcher = registry.unregister_matcher,
  list_decorators = registry.list_decorators,
  list_matchers = registry.list_matchers,
  get_decorator = registry.get_decorator,
  get_matcher = registry.get_matcher,
  registry = registry,
}
