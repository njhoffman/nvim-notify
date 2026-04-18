local M = {}

local LEVELS = { "trace", "debug", "info", "warn", "error", "fatal" }

local default_opts = {
  plugin = "nvim-notify",
  use_console = false,
  use_quickfix = false,
  use_file = true,
  outfile = nil,
  level = "info",
}

local function has_level_methods(tbl)
  if type(tbl) ~= "table" then
    return false
  end
  for _, name in ipairs(LEVELS) do
    if type(tbl[name]) ~= "function" then
      return false
    end
  end
  return true
end

local function wrap_level_fn(fn)
  local wrapped = {}
  for _, name in ipairs(LEVELS) do
    local level = name
    wrapped[name] = function(...)
      return fn(level, ...)
    end
  end
  return wrapped
end

local function build_default()
  return require("plenary.log").new(vim.deepcopy(default_opts))
end

local function resolve(user_value)
  if user_value == nil then
    return build_default()
  end

  if type(user_value) == "table" then
    if has_level_methods(user_value) then
      return user_value
    end
    local opts = vim.tbl_deep_extend("force", vim.deepcopy(default_opts), user_value)
    return require("plenary.log").new(opts)
  end

  if type(user_value) == "function" then
    local ok, result = pcall(user_value)
    if ok then
      if has_level_methods(result) then
        return result
      end
      if type(result) == "function" then
        return wrap_level_fn(result)
      end
    end
  end

  return build_default()
end

local logger = nil

function M.setup(user_value)
  logger = resolve(user_value)
  return logger
end

function M.get()
  if logger == nil then
    logger = build_default()
  end
  return logger
end

for _, name in ipairs(LEVELS) do
  local level = name
  M[level] = function(...)
    return M.get()[level](...)
  end
end

return M
