local log = require("notify.util.log")

local M = {}

local namespace = vim.api.nvim_create_namespace("nvim-notify")

function M.namespace()
  return namespace
end

--- Wrap `vim.api.nvim_buf_set_extmark` so a single bad extmark logs rather
--- than aborting the whole render.
---@param bufnr integer
---@param line integer
---@param col integer
---@param opts table
function M.set_extmark(bufnr, line, col, opts)
  local ok, err = pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, line, col, opts)
  if not ok then
    log.error("notify render: failed to set extmark", err)
  end
  return ok
end

--- Apply the body highlight for `notif` starting at `(start_line, start_col)`.
--- The highlight group key is `notif.body_hl_group` when set, otherwise "body".
---@param bufnr integer
---@param buf_highlights table
---@param notif table
---@param start_line integer
---@param start_col integer
---@param end_line integer inclusive-end line for the extmark
---@param end_col integer? optional inclusive-end column
function M.highlight_body(bufnr, buf_highlights, notif, start_line, start_col, end_line, end_col)
  local body_hl = notif.body_hl_group or "body"
  local opts = {
    hl_group = buf_highlights[body_hl] or buf_highlights.body,
    end_line = end_line,
    priority = 50,
  }
  if end_col ~= nil then
    opts.end_col = end_col
  end
  return M.set_extmark(bufnr, start_line, start_col, opts)
end

--- Apply inline highlight ranges from `notif.highlights.inline`.
---
--- Each entry is `{ hl_group_name, row, start_col, end_col }` where row/cols
--- are offsets within the body (row is 0-indexed from the first message
--- line, cols are byte columns). The group name is resolved via
--- `buf_highlights.content`, which is pre-populated by the buffer highlights
--- module so the inline group participates in opacity animations.
---@param bufnr integer
---@param buf_highlights table
---@param notif table
---@param start_line integer row where the body begins in the buffer
---@param start_col integer column where the body begins on its first line
function M.highlight_inline(bufnr, buf_highlights, notif, start_line, start_col)
  local inline = vim.tbl_get(notif, "highlights", "inline")
  if not inline then
    return
  end
  local content = buf_highlights.content or {}
  for _, hl in ipairs(inline) do
    local hl_group = content[hl[1]] or hl[1]
    M.set_extmark(bufnr, start_line + hl[2], start_col + hl[3], {
      hl_group = hl_group,
      end_col = start_col + hl[4],
      priority = 60,
    })
  end
end

--- Append the duplicate count to a title.
---@param title string
---@param notif table
---@param fmt string? printf format, default `"%s (x%d)"`
---@return string
function M.apply_duplicates(title, notif, fmt)
  if not notif.duplicates or #notif.duplicates == 0 then
    return title
  end
  return string.format(fmt or "%s (x%d)", title, #notif.duplicates)
end

--- Slice a string into pieces of `width` characters.
---@param line string
---@param width integer
---@return string[]
function M.split_length(line, width)
  local out = {}
  if width <= 0 then
    return out
  end
  while #line > 0 do
    out[#out + 1] = line:sub(1, width)
    line = line:sub(width + 1)
  end
  return out
end

--- Wrap each entry in `lines` to `max_width`, optionally padding.
---@param lines string[]
---@param max_width integer
---@param opts table? `{ pad_left = string?, pad_right = string? }`
---@return string[]
function M.custom_wrap(lines, max_width, opts)
  opts = opts or {}
  local pad_left = opts.pad_left or ""
  local pad_right = opts.pad_right or ""
  local inner_width = math.max(1, max_width - #pad_right)
  local wrapped = {}
  for _, line in ipairs(lines) do
    for _, piece in ipairs(M.split_length(line, inner_width)) do
      piece = piece:gsub("^%s+", ""):gsub("%s+$", "")
      wrapped[#wrapped + 1] = pad_left .. piece .. pad_right
    end
  end
  return wrapped
end

--- Return whether the message would overflow `config.max_width` and needs
--- a wrapping renderer. Intended as a rule predicate.
---@param notif table
---@param config table the config accessor object passed to renderers
---@return boolean
function M.needs_wrap(notif, config)
  local util = require("notify.util")
  local max = config and config.max_width and config.max_width() or nil
  if not max then
    return false
  end
  return util.max_line_width(notif.message) > max
end

local function has_title(notif)
  return type(notif.title) == "table" and type(notif.title[1]) == "string" and #notif.title[1] > 0
end

--- Built-in rulesets. Each ruleset is an ordered list of
--- `{ when = fn(notif, config) -> bool, pick = <renderer name> }`. A rule
--- with no `when` always matches and acts as the fallback. First match
--- wins.
local rulesets = {
  default = {
    {
      when = function(notif)
        return notif.captures and notif.captures.isError
      end,
      pick = "error",
    },
    {
      when = function(notif)
        return not has_title(notif) and #notif.message == 1
      end,
      pick = "minimal",
    },
    {
      when = function(notif)
        return not has_title(notif)
      end,
      pick = "wrapped-minimal",
    },
    {
      when = function(notif, config)
        return M.needs_wrap(notif, config)
      end,
      pick = "wrapped-default",
    },
    { pick = "default" },
  },
  compact = {
    {
      when = function(notif)
        return notif.captures and notif.captures.isError
      end,
      pick = "error",
    },
    {
      when = function(notif, config)
        return M.needs_wrap(notif, config)
      end,
      pick = "wrapped-compact",
    },
    { pick = "compact" },
  },
}

---@return string[] registered ruleset names
function M.rulesets()
  return vim.tbl_keys(rulesets)
end

---@param name string
---@return table? rules for the named ruleset
function M.get_ruleset(name)
  return rulesets[name]
end

--- Register (or replace) a named ruleset.
---@param name string
---@param rules table list of `{ when?, pick }` entries
function M.register_ruleset(name, rules)
  rulesets[name] = rules
end

--- Insert `rule` into the named ruleset. Defaults to position 1 (highest
--- priority). Creates the ruleset if it does not exist.
---@param name string
---@param rule table `{ when?, pick }`
---@param position integer? 1-based index, nil = prepend
function M.add_rule(name, rule, position)
  rulesets[name] = rulesets[name] or {}
  table.insert(rulesets[name], position or 1, rule)
end

--- Resolve which ruleset to use given the plugin config. Explicit
--- `config.render_ruleset` wins; otherwise `config.compact` toggles to the
--- "compact" ruleset; otherwise "default".
---@param config table
---@return string
function M.resolve_ruleset(config)
  if
    config
    and config.render_ruleset
    and type(config.render_ruleset) == "function"
    and config.render_ruleset()
  then
    return config.render_ruleset()
  end
  if config and config.compact and type(config.compact) == "function" and config.compact() then
    return "compact"
  end
  return "default"
end

--- Pick the renderer name for `notif` by walking the resolved ruleset.
---@param notif table
---@param config table
---@return string renderer name; falls back to "default" if nothing matches
function M.pick_renderer(notif, config)
  local name = M.resolve_ruleset(config)
  local rules = rulesets[name] or rulesets.default
  for _, rule in ipairs(rules) do
    if not rule.when or rule.when(notif, config) then
      return rule.pick
    end
  end
  return "default"
end

--- Render entry point used by the "auto" renderer. Picks a renderer by
--- rule and delegates.
function M.dispatch(bufnr, notif, highlights, config)
  local name = M.pick_renderer(notif, config)
  local renderer = require("notify.render")[name]
  return renderer(bufnr, notif, highlights, config)
end

return M
