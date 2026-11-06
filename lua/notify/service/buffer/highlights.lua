local util = require("notify.util")

---@class NotifyBufHighlights
---@field groups table
---@field opacity number
---@field title string
---@field border string
---@field icon string
---@field body string
---@field buffer number
---@field namespace number|nil Per-window highlight namespace holding the faded colours
---@field _config table
---@field _applied table<string, {fg: number|nil, bg: number|nil}> Last colours written per group
---@field _attached_win number|nil
local NotifyBufHighlights = {}

-- Namespaces cannot be deleted, so they are recycled rather than created per notification.
local free_namespaces = {}
local namespace_count = 0

local function acquire_namespace()
  local ns = table.remove(free_namespaces)
  if ns then
    return ns
  end
  namespace_count = namespace_count + 1
  return vim.api.nvim_create_namespace("nvim-notify-opacity-" .. namespace_count)
end

function NotifyBufHighlights:new(notif, buffer, config)
  local level = notif.level or "INFO"

  local function linked_group(section, skip_prefix, skip_level)
    local orig = (skip_prefix and "" or "Notify") .. (skip_level and "" or level) .. section
    if vim.fn.hlID(orig) == 0 then
      orig = "NotifyINFO" .. section
    end
    local new = orig .. buffer

    vim.api.nvim_set_hl(0, new, { link = orig })
    local hl = vim.api.nvim_get_hl(0, { name = orig, create = false, link = false })
    -- Removes the unwanted 'default' key, as we will copy the table for updating the highlight later.
    hl.default = nil
    return new, hl
  end

  local title, title_def = linked_group("Title")
  local border, border_def = linked_group("Border")
  local body, body_def = linked_group("Body")
  local icon, icon_def = linked_group("Icon")

  local groups = {
    [title] = title_def,
    [border] = border_def,
    [body] = body_def,
    [icon] = icon_def,
  }

  local inline_hls = vim.tbl_get(notif, "highlights", "inline")
  local level_hls = vim.tbl_get(notif, "highlights", "levels")

  local content = {}
  if inline_hls then
    -- predefined content highlights  { "Comment", 3, 9, 14 }
    for _, hl_group in ipairs(inline_hls) do
      local _content, _content_def = linked_group(hl_group[1], true, true)
      groups[_content] = _content_def
      content[hl_group[1]] = _content
    end
  elseif level_hls then
    -- special field for custom highlights for each level
    for _, hl_group in ipairs(level_hls) do
      local _content, _content_def = linked_group(hl_group[1], true, false)
      groups[_content] = _content_def
      content[hl_group[1]] = _content
    end
  end

  local buf_highlights = {
    groups = groups,
    opacity = 0,
    border = border,
    body = body,
    title = title,
    icon = icon,
    content = content,
    buffer = buffer,
    background_colour = config.background_colour(),
    _config = config,
    _applied = {},
  }
  self.__index = self

  setmetatable(buf_highlights, self)
  return buf_highlights
end

function NotifyBufHighlights:_redefine_treesitter()
  local buf_highlighter = require("vim.treesitter.highlighter").active[self.buffer]

  if not buf_highlighter then
    return
  end
  local render_namespace = vim.api.nvim_create_namespace("notify-treesitter-override")
  vim.api.nvim_buf_clear_namespace(self.buffer, render_namespace, 0, -1)

  local function link(orig)
    local new = orig .. self.buffer
    if self.groups[new] then
      return new
    end
    vim.api.nvim_set_hl(0, new, { link = orig })
    self.groups[new] = vim.api.nvim_get_hl(0, { name = new, link = false })
    return new
  end

  local matches = {}

  local i = 0
  buf_highlighter.tree:for_each_tree(function(tstree, tree)
    if not tstree then
      return
    end

    local root = tstree:root()

    local query = buf_highlighter:get_query(tree:lang())

    -- Some injected languages may not have highlight queries.
    if not query:query() then
      return
    end

    local iter = query:query():iter_captures(root, buf_highlighter.bufnr)

    for capture, node, metadata in iter do
      -- Wait until we get at least a single capture as we don't know when parsing is complete.
      self._treesitter_redefined = true
      local hl = query.hl_cache[capture]

      if hl then
        i = i + 1
        local c = query._query.captures[capture] -- name of the capture in the query
        if c ~= nil then
          local capture_hl
          -- Removed in nightly with change of highlight names to @...
          -- https://github.com/neovim/neovim/pull/19931
          if query._get_hl_from_capture then
            local general_hl, is_vim_hl = query:_get_hl_from_capture(capture)
            capture_hl = is_vim_hl and general_hl or (tree:lang() .. general_hl)
          else
            capture_hl = query._query.captures[capture]
            if not vim.startswith(capture_hl, "_") then
              capture_hl = "@" .. capture_hl .. "." .. tree:lang()
            end
          end

          local start_row, start_col, end_row, end_col = node:range()
          local custom_hl = link(capture_hl)

          vim.api.nvim_buf_set_extmark(self.buffer, render_namespace, start_row, start_col, {
            end_row = end_row,
            end_col = end_col,
            hl_group = custom_hl,
            -- TODO: Not sure how neovim's highlighter doesn't have issues with overriding highlights
            -- Three marks on same region always show the second for some reason AFAICT
            priority = tonumber(metadata.priority) or i + 200,
            conceal = metadata.conceal,
          })
        end
      end
    end
  end, true)
  return matches
end

--- Use this object's faded colours in `win`. Does nothing until a fade has started.
---@param win number
function NotifyBufHighlights:attach(win)
  if self.namespace and self._attached_win ~= win then
    vim.api.nvim_win_set_hl_ns(win, self.namespace)
    self._attached_win = win
  end
end

--- Fade the groups towards the background colour. The colours are written to a namespace used only
--- by this notification's window, because changing a global group makes Neovim repaint every
--- window on the screen.
---@param alpha number
---@return boolean updated Whether any colour changed
function NotifyBufHighlights:set_opacity(alpha)
  if
    not self._treesitter_redefined
    and vim.api.nvim_get_option_value("filetype", { buf = self.buffer }) ~= "notify"
  then
    self:_redefine_treesitter()
  end
  self.opacity = alpha
  if next(self.groups) == nil then
    return false
  end
  self.namespace = self.namespace or acquire_namespace()
  local background = self._config.background_colour()
  local updated = false
  for group, fields in pairs(self.groups) do
    local fg = fields.fg and util.blend(fields.fg, background, alpha / 100)
    local bg = fields.bg and util.blend(fields.bg, background, alpha / 100)
    local applied = self._applied[group]
    if not applied or applied.fg ~= fg or applied.bg ~= bg then
      local hl = vim.tbl_extend("force", fields, { fg = fg, bg = bg })
      vim.api.nvim_set_hl(self.namespace, group, hl)
      self._applied[group] = { fg = fg, bg = bg }
      updated = true
    end
  end
  if not self._attached_win then
    local win = vim.fn.bufwinid(self.buffer)
    if win ~= -1 then
      self:attach(win)
    end
  end
  return updated
end

function NotifyBufHighlights:get_opacity()
  return self.opacity
end

function NotifyBufHighlights:clear()
  for group, _ in pairs(self.groups) do
    vim.api.nvim_set_hl(0, group, {})
    if self.namespace then
      vim.api.nvim_set_hl(self.namespace, group, {})
    end
  end
  self.groups = {}
  self._applied = {}
  if self.namespace then
    table.insert(free_namespaces, self.namespace)
    self.namespace = nil
  end
  self._attached_win = nil
end

---@return NotifyBufHighlights
return function(level, buffer, config)
  return NotifyBufHighlights:new(level, buffer, config)
end
