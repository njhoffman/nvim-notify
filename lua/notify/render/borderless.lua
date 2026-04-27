local api = vim.api
local base = require("notify.render.base")

local function resolve_title(notif)
  local raw = notif.title_input
  if type(raw) == "string" and #raw > 0 then
    return raw
  end
  if type(raw) == "table" and type(raw[1]) == "string" and #raw[1] > 0 then
    return raw[1]
  end
  return ""
end

return function(bufnr, notif, highlights)
  local message = notif.message
  api.nvim_buf_set_lines(bufnr, 0, -1, false, message)

  local icon = notif.icon or ""
  local icon_w = icon == "" and 0 or vim.fn.strwidth(icon)

  if icon ~= "" then
    base.set_extmark(bufnr, 0, 0, {
      virt_text = { { icon .. " ", highlights.icon } },
      virt_text_pos = "inline",
      priority = 10,
    })
  end

  local title_text = base.apply_duplicates(resolve_title(notif), notif)
  if #title_text > 0 then
    base.set_extmark(bufnr, 0, 0, {
      virt_text = { { " " }, { title_text, highlights.title }, { " " } },
      virt_text_pos = "right_align",
      priority = 10,
    })
  end

  if icon_w > 0 then
    local pad = string.rep(" ", icon_w + 1)
    for ln = 1, #message - 1 do
      base.set_extmark(bufnr, ln, 0, {
        virt_text = { { pad, highlights.body } },
        virt_text_pos = "inline",
        priority = 50,
      })
    end
  end

  base.highlight_body(bufnr, highlights, notif, 0, 0, #message - 1, #message[#message])
  base.highlight_inline(bufnr, highlights, notif, 0, 0)
end
