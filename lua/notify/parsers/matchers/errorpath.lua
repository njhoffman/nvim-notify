--- `errorpath` matcher: detects common `file:line` and `file:line:col`
--- patterns in the first line of the message. Populates captures
--- `{ errorPath, errorFile, errorLine, errorCol? }` and adds an inline
--- highlight over the matched span so renderers can emphasise it.

local M = {}

-- Patterns tried in order. The order matters: the more specific pattern
-- (file:line:col) must come before file:line so it wins the match.
local PATTERNS = {
  -- path:line:col where path contains at least one path segment or a dot
  { pattern = "([%w%._/%-\\]+):(%d+):(%d+)", has_col = true },
  { pattern = "([%w%._/%-\\]+):(%d+)", has_col = false },
}

local function find_first_match(msg)
  -- Only scan the first line — errors usually put the path there.
  local first = msg:match("^[^\n]*") or msg
  for _, spec in ipairs(PATTERNS) do
    local s, e, a, b, c = first:find(spec.pattern)
    if s then
      local file = a
      local line = tonumber(b)
      if not line then
        -- Reject matches where the line group failed to parse as an int
        -- (defensive: pattern should guarantee %d+, but %s may be empty).
      else
        -- Reject matches where "file" has no path-like character — the
        -- pattern is greedy enough that "foo:12" (a plain word + number)
        -- will match. Require at least a dot or slash to treat it as a
        -- real path.
        if file:find("[./\\]") then
          return {
            start_col = s - 1,
            end_col = e,
            file = file,
            line = line,
            col = spec.has_col and tonumber(c) or nil,
            full = first:sub(s, e),
          }
        end
      end
    end
  end
end

function M.register(registry)
  registry.register_matcher("errorpath", {
    match = function(msg)
      if type(msg) ~= "string" then
        return nil
      end
      local hit = find_first_match(msg)
      if not hit then
        return nil
      end
      return {
        isError = true,
        errorPath = hit.full,
        errorFile = hit.file,
        errorLine = hit.line,
        errorCol = hit.col,
        errorBounds = { 0, hit.start_col, hit.end_col },
      }
    end,
    highlights = function(_, caps)
      local b = caps.errorBounds
      if not b then
        return {}
      end
      return { { "NotifyERRORTitle", b[1], b[2], b[3] } }
    end,
  })
end

M._find_first_match = find_first_match

return M
