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
    local got_text, text = pcall(vim.api.nvim_buf_get_lines, bufnr, line, line + 1, false)
    local length = got_text and text[1] and #text[1] or "none"
    log.error(
      string.format(
        "notify render: failed to set extmark at line %d, col %d, end_col %s, line length %s:",
        line,
        col,
        tostring(opts.end_col),
        length
      ),
      err
    )
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
---
--- `start_col` only shifts the first body row: a prefix such as an icon sits on that row alone.
--- For a body that was wrapped, use `highlight_inline_wrapped`.
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
    local offset = hl[2] == 0 and start_col or 0
    M.set_extmark(bufnr, start_line + hl[2], offset + hl[3], {
      hl_group = content[hl[1]] or hl[1],
      end_col = offset + hl[4],
      priority = 60,
    })
  end
end

--- Apply `notif.highlights.inline` to a body wrapped by `custom_wrap`. The ranges describe the
--- original message, so each one is placed on every wrapped line it overlaps.
---@param bufnr integer
---@param buf_highlights table
---@param notif table
---@param start_line integer row where the wrapped body begins in the buffer
---@param segments table[] second return value of `custom_wrap`
function M.highlight_inline_wrapped(bufnr, buf_highlights, notif, start_line, segments)
  local inline = vim.tbl_get(notif, "highlights", "inline")
  if not inline then
    return
  end
  local content = buf_highlights.content or {}
  for _, hl in ipairs(inline) do
    for index, segment in ipairs(segments) do
      local first = math.max(hl[3], segment.start)
      local last = math.min(hl[4], segment.finish)
      if segment.row == hl[2] and first < last then
        local shift = segment.col - segment.start
        M.set_extmark(bufnr, start_line + index - 1, first + shift, {
          hl_group = content[hl[1]] or hl[1],
          end_col = last + shift,
          priority = 60,
        })
      end
    end
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

--- Shorten `text` to at most `max_cells` display cells, ending in an ellipsis if it was cut.
---@param text string
---@param max_cells integer
---@return string
function M.truncate(text, max_cells)
  if vim.fn.strdisplaywidth(text) <= max_cells then
    return text
  end
  if max_cells <= 1 then
    return "…"
  end
  local kept = M.split_length(text, max_cells - 1)[1]
  -- split_length always takes one character, which may be wider than the space left.
  if vim.fn.strdisplaywidth(kept) > max_cells - 1 then
    return "…"
  end
  return kept .. "…"
end

--- Add the duplicate count to a title and shorten it to fit. The count is never cut off.
---@param title string
---@param notif table
---@param available integer? cells the result may use, nil for no limit
---@param fmt string? printf format for the duplicate count, see `apply_duplicates`
---@return string
function M.fit_title(title, notif, available, fmt)
  local full = M.apply_duplicates(title, notif, fmt)
  if not available or vim.fn.strdisplaywidth(full) <= available then
    return full
  end
  local count_width = vim.fn.strdisplaywidth(full) - vim.fn.strdisplaywidth(title)
  return M.apply_duplicates(M.truncate(title, math.max(1, available - count_width)), notif, fmt)
end

--- The configured maximum window width, if there is one.
---@param config table? the config accessor object passed to renderers
---@return integer?
function M.max_width(config)
  return config and config.max_width and config.max_width() or nil
end

--- Byte length of the UTF-8 character at `index`. Invalid bytes count as one byte each, so pieces
--- of a line always join back into the original.
---@param line string
---@param index integer
---@return integer
local function char_length(line, index)
  local byte = line:byte(index)
  local length = 1
  if byte >= 0xC2 and byte <= 0xDF then
    length = 2
  elseif byte >= 0xE0 and byte <= 0xEF then
    length = 3
  elseif byte >= 0xF0 and byte <= 0xF4 then
    length = 4
  end
  for following = index + 1, index + length - 1 do
    local next_byte = line:byte(following)
    if not next_byte or next_byte < 0x80 or next_byte > 0xBF then
      return 1
    end
  end
  return length
end

--- Slice a string into pieces of at most `width` display cells, without cutting a character.
--- Combining characters stay with the character before them. A character wider than `width` gets a
--- piece of its own.
---@param line string
---@param width integer
---@param first_width integer? Width of the first piece, default `width`
---@return string[]
function M.split_length(line, width, first_width)
  local out = {}
  if width <= 0 then
    return out
  end
  local limit = first_width or width
  local piece_start = 1
  local used = 0
  local index = 1
  while index <= #line do
    local length = char_length(line, index)
    local char_end = index + length - 1
    local byte = line:byte(index)
    local width_with_char = used + 1
    if byte < 0x20 or byte >= 0x7F then
      -- Measured with the text before it: a combining character alone reports one cell.
      width_with_char = vim.fn.strdisplaywidth(line:sub(piece_start, char_end))
    end
    if used > 0 and width_with_char > limit then
      out[#out + 1] = line:sub(piece_start, index - 1)
      piece_start = index
      limit = width
      width_with_char = vim.fn.strdisplaywidth(line:sub(index, char_end))
    end
    used = width_with_char
    index = index + length
  end
  if piece_start <= #line then
    out[#out + 1] = line:sub(piece_start)
  end
  return out
end

--- Wrap each entry in `lines` to `max_width`, optionally padding.
---@param lines string[]
---@param max_width integer
---@param opts table? `{ pad_left = string?, pad_right = string?, first_line_reserve = integer? }`
--- `first_line_reserve` keeps that many cells free on the first wrapped line, for text the renderer
--- prepends to it.
---@return string[] wrapped
---@return table[] segments For each wrapped line, where its text came from: `row` and the byte range
--- `start` to `finish` in the original lines, and `col`, the byte column it begins at in the wrapped
--- line. A renderer that prepends text to a wrapped line must add that length to `col`.
function M.custom_wrap(lines, max_width, opts)
  opts = opts or {}
  local pad_left = opts.pad_left or ""
  local pad_right = opts.pad_right or ""
  local padding = vim.fn.strdisplaywidth(pad_left) + vim.fn.strdisplaywidth(pad_right)
  local inner_width = math.max(1, max_width - padding)
  local first_width = math.max(1, inner_width - (opts.first_line_reserve or 0))
  local wrapped = {}
  local segments = {}
  for row, line in ipairs(lines) do
    local offset = 0
    local line_first_width = #wrapped == 0 and first_width or inner_width
    -- split_length returns nothing for an empty line, which would lose the blank row.
    local pieces = line == "" and { "" } or M.split_length(line, inner_width, line_first_width)
    for _, piece in ipairs(pieces) do
      local leading = #piece:match("^%s*")
      local text = piece:sub(leading + 1):gsub("%s+$", "")
      wrapped[#wrapped + 1] = pad_left .. text .. pad_right
      segments[#segments + 1] = {
        row = row - 1,
        start = offset + leading,
        finish = offset + leading + #text,
        col = #pad_left,
      }
      offset = offset + #piece
    end
  end
  return wrapped, segments
end

--- The icon and title that the `compact` renderer puts before the message.
---@param notif table
---@param max_cells integer? shorten the title so the prefix uses at most this many cells
---@return string
function M.compact_prefix(notif, max_cells)
  local icon = notif.icon or ""
  -- The prefix around the title is "<icon> | <title>:".
  local available = max_cells and max_cells - vim.fn.strdisplaywidth(icon) - 4
  local title = M.fit_title(vim.tbl_get(notif, "title", 1) or "", notif, available, "%s x%d")
  if #title > 0 then
    return string.format("%s | %s:", icon, title)
  end
  return string.format("%s |", icon)
end

--- Return whether the `compact` renderer's lines would overflow `config.max_width`. Unlike
--- `needs_wrap` this includes the prefix on the first line.
---@param notif table
---@param config table the config accessor object passed to renderers
---@return boolean
function M.compact_needs_wrap(notif, config)
  local util = require("notify.util")
  local max = config and config.max_width and config.max_width() or nil
  if not max then
    return false
  end
  local lines = vim.deepcopy(notif.message)
  lines[1] = string.format("%s %s", M.compact_prefix(notif), lines[1] or "")
  return util.max_line_width(lines) > max
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
        return M.compact_needs_wrap(notif, config)
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
