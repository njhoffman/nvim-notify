---@tag notify.parsers
---@text
--- Registry for decorators and matchers that extend the notification
--- pipeline.
---
--- Decorator ~
---   Reads structured input from `opts.payload = { kind, data }` and
---   produces the displayed text plus inline highlights. Only one decorator
---   runs per notification — the first whose `trigger(opts)` returns true
---   wins.
---
--- Matcher ~
---   Inspects the final `msg` (after any decorator) and, on a hit, writes
---   `opts.captures` and optional inline highlights. First matcher wins.
---
--- Shape:
--- >lua
---     parsers.register_decorator("lines", {
---       trigger = function(opts) return opts.payload and opts.payload.kind == "lines" end,
---       format  = function(opts, config) return { msg = ..., highlights = {...}, captures = {...} } end,
---     })
---
---     parsers.register_matcher("error", {
---       match = function(msg, opts) -- return captures table on hit, nil on miss
---         local file, line = msg:match("^Error at ([^:]+):(%d+)")
---         if file then return { isError = true, file = file, line = tonumber(line) } end
---       end,
---       highlights = function(msg, caps) return { { "NotifyERRORTitle", 0, 0, 9 } } end, -- optional
---     })
--- <
---
--- Per-notification escape hatch: pass `opts.parser = false` to skip all
--- decorators and matchers.

local M = {}

local decorators = {}
local decorator_order = {}
local matchers = {}
local matcher_order = {}

---@param name string
---@param spec { trigger: fun(opts:table):boolean, format: fun(opts:table, config:table):table }
function M.register_decorator(name, spec)
  if decorators[name] == nil then
    table.insert(decorator_order, name)
  end
  decorators[name] = spec
end

---@param name string?
function M.unregister_decorator(name)
  if decorators[name] == nil then
    return
  end
  decorators[name] = nil
  for i, n in ipairs(decorator_order) do
    if n == name then
      table.remove(decorator_order, i)
      return
    end
  end
end

---@param name string
---@param spec { match: fun(msg:string, opts:table):table?, highlights: fun(msg:string, caps:table):table? }
function M.register_matcher(name, spec)
  if matchers[name] == nil then
    table.insert(matcher_order, name)
  end
  matchers[name] = spec
end

---@param name string
function M.unregister_matcher(name)
  if matchers[name] == nil then
    return
  end
  matchers[name] = nil
  for i, n in ipairs(matcher_order) do
    if n == name then
      table.remove(matcher_order, i)
      return
    end
  end
end

function M.list_decorators()
  return vim.deepcopy(decorator_order)
end

function M.list_matchers()
  return vim.deepcopy(matcher_order)
end

function M.get_decorator(name)
  return decorators[name]
end

function M.get_matcher(name)
  return matchers[name]
end

local function merge_highlights(opts, patch)
  if not patch then
    return
  end
  opts.highlights = opts.highlights or {}
  if patch.inline then
    opts.highlights.inline = opts.highlights.inline or {}
    vim.list_extend(opts.highlights.inline, patch.inline)
  end
  for k, v in pairs(patch) do
    if k ~= "inline" then
      opts.highlights[k] = v
    end
  end
end

local function merge_captures(opts, patch)
  if not patch then
    return
  end
  opts.captures = vim.tbl_deep_extend("force", opts.captures or {}, patch)
end

--- Run the decorator phase then the matcher phase.
---@param msg string
---@param level any
---@param opts table
---@param config table?
---@return string msg
---@return any level
---@return table opts
function M.run(msg, level, opts, config)
  opts = opts or {}
  if opts.parser == false then
    return msg, level, opts
  end

  for _, name in ipairs(decorator_order) do
    local dec = decorators[name]
    if dec and dec.trigger(opts) then
      local result = dec.format(opts, config) or {}
      if result.msg ~= nil then
        msg = result.msg
      end
      merge_highlights(opts, result.highlights)
      merge_captures(opts, result.captures)
      opts.captures = opts.captures or {}
      opts.captures.decorator = name
      break
    end
  end

  if type(msg) == "string" then
    for _, name in ipairs(matcher_order) do
      local m = matchers[name]
      if m then
        local caps = m.match(msg, opts)
        if caps then
          merge_captures(opts, caps)
          opts.captures.matcher = name
          if m.highlights then
            local inline = m.highlights(msg, caps) or {}
            merge_highlights(opts, { inline = inline })
          end
          break
        end
      end
    end
  end

  return msg, level, opts
end

--- Erase every registered decorator and matcher. Intended for tests.
function M.reset()
  decorators = {}
  decorator_order = {}
  matchers = {}
  matcher_order = {}
end

return M
