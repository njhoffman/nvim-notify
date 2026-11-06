-- Wrapping compact renderer. Emits either an `icon + title` header row
-- followed by a wrapped body, or inlines the icon with the first wrapped
-- line when the notification has no user-set title.
local base = require("notify.render.base")

---@param bufnr number
---@param notif table
---@param highlights table
---@param config table plugin config_obj
return function(bufnr, notif, highlights, config)
  local icon = notif.icon
  local title = notif.title[1]

  local max_width = config.max_width() or 80
  local message, segments =
    base.custom_wrap(notif.message, max_width, { pad_left = " ", pad_right = " " })

  local default_titles = { "Error", "Warning", "Notify" }
  local has_valid_manual_title = type(title) == "string"
    and #title > 0
    and not vim.tbl_contains(default_titles, title)

  local prefix
  -- Where the body starts: the row after a title row, or after the prefix on the first row.
  local body_line, body_col
  if has_valid_manual_title then
    prefix = base.apply_duplicates(string.format(" %s %s", icon, title), notif, "%s x%d")
    table.insert(message, 1, prefix)
    body_line, body_col = 1, 0
  else
    prefix = base.apply_duplicates(string.format(" %s", icon), notif, "%s x%d")
    message[1] = string.format("%s %s", prefix, message[1] or "")
    body_line, body_col = 0, #prefix + 1
    if segments[1] then
      segments[1].col = segments[1].col + body_col
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, message)

  local icon_length = string.len(icon)

  base.set_extmark(bufnr, 0, 0, {
    hl_group = highlights.icon,
    end_col = icon_length + 1,
    priority = 50,
  })
  base.set_extmark(bufnr, 0, icon_length + 1, {
    hl_group = highlights.title,
    end_col = has_valid_manual_title and #prefix or body_col,
    priority = 50,
  })
  base.highlight_body(bufnr, highlights, notif, body_line, body_col, #message)
  base.highlight_inline_wrapped(bufnr, highlights, notif, body_line, segments)
end
