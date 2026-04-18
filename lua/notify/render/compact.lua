local base = require("notify.render.base")

return function(bufnr, notif, highlights)
  local icon = notif.icon
  local title = base.apply_duplicates(notif.title[1], notif, "%s x%d")

  local prefix
  if type(title) == "string" and #title > 0 then
    prefix = string.format("%s | %s:", icon, title)
  else
    prefix = string.format("%s |", icon)
  end
  local message = {
    string.format("%s %s", prefix, notif.message[1]),
    unpack(notif.message, 2),
  }

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
