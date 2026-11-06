local base = require("notify.render.base")

return function(bufnr, notif, highlights, config)
  local icon = notif.icon
  local max_width = base.max_width(config)
  -- Shorten a long title before the message, which matters more, is pushed out of the window.
  local max_prefix = max_width and max_width - vim.fn.strdisplaywidth(notif.message[1]) - 1
  local prefix = base.compact_prefix(notif, max_prefix)
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
