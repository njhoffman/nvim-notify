local vim_api = vim.api
local base = require("notify.render.base")

---@param bufnr number
---@param notif notify.Record
---@param highlights notify.Highlights
---@param config notify.Config
return function(bufnr, notif, highlights, config)
  local icon = notif.icon .. " "
  local title = notif.title[1] or "Notify"

  local terminal_width = vim.o.columns
  local default_max_width = math.floor((terminal_width * 30) / 100)
  local max_width = config.max_width and config.max_width() or default_max_width
  max_width = math.max(10, math.min(max_width, terminal_width - 1))

  local message = base.custom_wrap(notif.message, max_width)

  local prefix = base.apply_duplicates(string.format(" %s %s", icon, title), notif, "%s x%d")
  table.insert(message, 1, prefix)
  table.insert(message, 2, string.rep("━", max_width))

  vim_api.nvim_buf_set_lines(bufnr, 0, -1, false, message)

  base.set_extmark(bufnr, 0, 0, {
    virt_text = {
      { " " },
      { icon, highlights.icon },
      { title, highlights.title },
      { " " },
    },
    virt_text_win_col = 0,
    priority = 10,
  })
  base.set_extmark(bufnr, 1, 0, {
    virt_text = { { string.rep("━", max_width), highlights.border } },
    virt_text_win_col = 0,
    priority = 10,
  })
  base.highlight_body(bufnr, highlights, notif, 2, 0, #message, 0)
  base.highlight_inline(bufnr, highlights, notif, 2, 0)
end
