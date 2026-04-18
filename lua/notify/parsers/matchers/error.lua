--- `error` matcher: parses Neovim-shaped error messages into structured
--- captures for the `error` renderer.
---
--- Strategy:
---   1. Walk lines looking for a `path:line:` pair where the path has at
---      least one dot, slash, or backslash (rejects plain `word:number`).
---   2. Pick the *innermost* (rightmost) triple on the first such line —
---      this unwraps nested `Vim(...):ECode:` / `vim/_editor.lua:0:` prefixes
---      so the user's actual frame is captured.
---   3. An E-code is taken from the first line that contains one, even if
---      that line doesn't itself carry the triple (e.g. when neovim prints
---      `E5108:Error executing lua\n  user/path.lua:N:msg`).
---   4. Stack frames are grouped by `stack traceback:` markers when
---      present, otherwise all remaining non-empty lines form one group.
---
--- Captures:
---   isError, errorCode?, errorFile, errorLine, errorMessage,
---   errorTitle (raw title line), errorStackgroups.

local M = {}

local TRIPLE = "([%w%._/%-\\~]+):(%d+):"

local function is_path_like(s)
  return type(s) == "string" and s:find("[./\\]") ~= nil
end

local function trim(s)
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

-- Find all valid `path:line:` positions in a single line. Returns a list
-- of { file, line, finish } entries in left-to-right order.
local function all_triples(line)
  local out = {}
  local start = 1
  while true do
    local s, e, f, l = line:find(TRIPLE, start)
    if not s then
      break
    end
    if is_path_like(f) then
      table.insert(out, { file = f, line = tonumber(l), finish = e })
    end
    start = e + 1
  end
  return out
end

local function extract_code(line)
  return line:match("(E%d+)")
end

local function find_title(lines)
  for i, raw in ipairs(lines) do
    local triples = all_triples(raw)
    if #triples > 0 then
      local last = triples[#triples]
      local message = trim(raw:sub(last.finish + 1))
      return i, last.file, last.line, message
    end
  end
end

local function find_stack_marker(lines)
  for i, line in ipairs(lines) do
    if line:match("stack traceback:") then
      return i
    end
  end
end

local function collect_stackgroups(lines, title_idx)
  local marker_idx = find_stack_marker(lines)
  local groups = {}

  if marker_idx then
    local current
    for i = marker_idx, #lines do
      local raw = lines[i]
      if raw:match("^%s*stack traceback:%s*$") then
        current = {}
        table.insert(groups, current)
      elseif current then
        local t = trim(raw)
        if #t > 0 then
          table.insert(current, t)
        end
      end
    end
    return groups
  end

  -- No marker: treat non-empty lines after the title line as one group
  -- if any exist. This handles compact neovim output that skips the
  -- `stack traceback:` header.
  local group = {}
  for i = (title_idx or 0) + 1, #lines do
    local t = trim(lines[i])
    if #t > 0 then
      table.insert(group, t)
    end
  end
  if #group > 0 then
    table.insert(groups, group)
  end
  return groups
end

local function parse(msg)
  if type(msg) ~= "string" or msg == "" then
    return nil
  end
  local lines = vim.split(msg, "\n", { plain = true })

  local title_idx, file, line_num, message = find_title(lines)
  if not file then
    return nil
  end

  local code
  for i = 1, title_idx do
    local c = extract_code(lines[i])
    if c then
      code = c
      break
    end
  end

  local title_line = trim(lines[title_idx] or "")
  local stackgroups = collect_stackgroups(lines, title_idx)

  return {
    isError = true,
    errorCode = code,
    errorFile = file,
    errorLine = line_num,
    errorMessage = message,
    errorTitle = title_line,
    errorStackgroups = stackgroups,
  }
end

function M.register(registry)
  registry.register_matcher("error", {
    match = function(msg)
      return parse(msg)
    end,
    -- Highlight application is handled by the `error` renderer; no inline
    -- ranges are produced here.
  })
end

M._parse = parse

return M
