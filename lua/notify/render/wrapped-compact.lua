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
  local message = base.custom_wrap(notif.message, max_width, { pad_left = " ", pad_right = " " })

  local default_titles = { "Error", "Warning", "Notify" }
  local has_valid_manual_title = type(title) == "string"
    and #title > 0
    and not vim.tbl_contains(default_titles, title)

  local prefix
  if has_valid_manual_title then
    prefix = base.apply_duplicates(string.format(" %s %s", icon, title), notif, "%s x%d")
    table.insert(message, 1, prefix)
  else
    prefix = base.apply_duplicates(string.format(" %s", icon), notif, "%s x%d")
    message[1] = string.format("%s %s", prefix, message[1])
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, message)

  local icon_length = string.len(icon)
  local prefix_length = string.len(prefix)

  base.set_extmark(bufnr, 0, 0, {
    hl_group = highlights.icon,
    end_col = icon_length + 1,
    priority = 50,
  })
  base.set_extmark(bufnr, 0, icon_length + 1, {
    hl_group = highlights.title,
    end_col = prefix_length + 1,
    priority = 50,
  })
  base.highlight_body(bufnr, highlights, notif, 0, prefix_length + 1, #message)
  base.highlight_inline(bufnr, highlights, notif, 0, prefix_length + 1)
end
