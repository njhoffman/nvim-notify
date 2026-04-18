--- `error` renderer: lays out structured error captures from the `error`
--- matcher. Expects `notif.captures.isError`; falls back to the default
--- renderer if the captures are missing (e.g. when the user picks this
--- renderer explicitly without the matcher having run).
---
--- Layout:
---     [code]: [title]                -- code omitted if absent
---     [file]:[line]: [message]       -- second line, file-linked if path exists
---     [stack frame]                  -- one per line, indented by 2 spaces
---     [stack frame]
---     ...                            -- blank line between traceback groups

local api = vim.api
local base = require("notify.render.base")

local HL = {
  code = "NotifyERRORCode",
  title = "NotifyERRORMain",
  file = "NotifyERRORFile",
  file_linked = "NotifyERRORFileLinked",
  line = "NotifyERRORLine",
  message = "NotifyERRORMessage",
  stack = "NotifyERRORStack",
}

local function shorten(path)
  if type(path) ~= "string" or path == "" then
    return path
  end
  local home = os.getenv("HOME")
  if home and path:sub(1, #home) == home then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

local function file_exists(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  if path:match("%.%.%.") then
    return false
  end
  local ok, stat = pcall(vim.loop.fs_stat, path)
  return ok and stat and stat.type == "file" or false
end

return function(bufnr, notif, highlights, _config)
  local captures = notif.captures or {}
  if not captures.isError then
    -- Not an error we can render structurally; delegate to default.
    return require("notify.render.default")(bufnr, notif, highlights, _config)
  end

  local code = captures.errorCode
  local title = captures.errorTitle or ""
  local file = captures.errorFile or ""
  local line = captures.errorLine and tostring(captures.errorLine) or ""
  local message = captures.errorMessage or ""
  local stackgroups = captures.errorStackgroups or {}

  local short = shorten(file)
  local linked = file_exists(file)
  if linked then
    pcall(api.nvim_buf_set_var, bufnr, "notify_file", file)
    pcall(api.nvim_buf_set_var, bufnr, "notify_line", captures.errorLine)
  end

  local lines = {}

  -- Line 1: [code: ]title
  local line1 = title
  if code and #code > 0 then
    line1 = code .. ": " .. title
  end
  lines[#lines + 1] = line1

  -- Line 2: file:line: message
  local line2 = string.format("%s:%s: %s", short, line, message)
  lines[#lines + 1] = line2

  -- Lines 3+: stackgroups, blank-separated
  for gi, group in ipairs(stackgroups) do
    if gi > 1 then
      lines[#lines + 1] = ""
    end
    for _, frame in ipairs(group) do
      lines[#lines + 1] = "  " .. frame
    end
  end

  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Highlights
  if code and #code > 0 then
    base.set_extmark(bufnr, 0, 0, {
      hl_group = HL.code,
      end_col = #code + 1,
      priority = 50,
    })
    base.set_extmark(bufnr, 0, #code + 2, {
      hl_group = HL.title,
      end_col = #line1,
      priority = 50,
    })
  else
    base.set_extmark(bufnr, 0, 0, {
      hl_group = HL.title,
      end_col = #line1,
      priority = 50,
    })
  end

  -- File path
  base.set_extmark(bufnr, 1, 0, {
    hl_group = linked and HL.file_linked or HL.file,
    end_col = #short,
    priority = 50,
  })
  -- Line number
  local line_start = #short + 1
  base.set_extmark(bufnr, 1, line_start, {
    hl_group = HL.line,
    end_col = line_start + #line,
    priority = 50,
  })
  -- Message
  local msg_start = line_start + #line + 2
  if msg_start < #line2 then
    base.set_extmark(bufnr, 1, msg_start, {
      hl_group = HL.message,
      end_col = #line2,
      priority = 50,
    })
  end

  -- Stack frames
  local row = 2
  for gi, group in ipairs(stackgroups) do
    if gi > 1 then
      row = row + 1
    end
    for _, _frame in ipairs(group) do
      base.set_extmark(bufnr, row, 0, {
        hl_group = HL.stack,
        end_col = #lines[row + 1],
        priority = 50,
      })
      row = row + 1
    end
  end

  -- Inline highlights from opts.highlights.inline (if the user supplied any)
  base.highlight_inline(bufnr, highlights, notif, 0, 0)
end
