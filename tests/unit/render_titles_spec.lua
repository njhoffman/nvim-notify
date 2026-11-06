local base = require("notify.render.base")
local render = require("notify.render")

local HIGHLIGHTS =
  { title = "Title", icon = "Icon", border = "Border", body = "Body", content = {} }
local width_of = vim.fn.strdisplaywidth

--- Render a notification and return everything drawn on its title row.
---@return string[] texts each buffer line and virtual text in the top rows
---@return table lines all buffer lines
local function draw(name, title_input, max_width, extra)
  local title = type(title_input) == "table" and title_input or { title_input, "12:00" }
  local buf = vim.api.nvim_create_buf(false, true)
  local config = {
    max_width = function()
      return max_width
    end,
    minimum_width = function()
      return 3
    end,
  }
  render[name](
    buf,
    vim.tbl_extend("force", {
      title = title,
      title_input = title_input,
      icon = "I",
      level = "INFO",
      message = { "body" },
    }, extra or {}),
    HIGHLIGHTS,
    config
  )
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local texts = { lines[1] }
  local marks = vim.api.nvim_buf_get_extmarks(buf, base.namespace(), 0, -1, { details = true })
  for _, mark in ipairs(marks) do
    local text = ""
    for _, chunk in ipairs(mark[4].virt_text or {}) do
      text = text .. chunk[1]
    end
    if text ~= "" then
      table.insert(texts, text)
    end
  end
  vim.api.nvim_buf_delete(buf, { force = true })
  return texts, lines
end

local RENDERERS =
  { "default", "simple", "wrapped-default", "wrapped-compact", "inline", "borderless" }

describe("truncate()", function()
  it("leaves text that fits", function()
    assert.equals("hello", base.truncate("hello", 5))
  end)

  it("shortens text and marks the cut", function()
    assert.equals("hel…", base.truncate("hello", 4))
  end)

  it("counts display cells, not bytes", function()
    assert.equals("héllo", base.truncate("héllo", 5))
    assert.equals("hé…", base.truncate("héllo", 3))
  end)

  it("does not split a wide character", function()
    assert.equals("日…", base.truncate("日本語", 4))
    assert.equals("…", base.truncate("日本語", 2))
  end)

  it("returns only the ellipsis when there is no room", function()
    assert.equals("…", base.truncate("hello", 1))
    assert.equals("…", base.truncate("hello", 0))
  end)
end)

describe("fit_title()", function()
  local dupes = { duplicates = { 1, 2, 3 } }

  it("adds the duplicate count with no limit", function()
    assert.equals("title (x3)", base.fit_title("title", dupes))
  end)

  it("leaves a title that fits", function()
    assert.equals("title (x3)", base.fit_title("title", dupes, 10))
    assert.equals("title", base.fit_title("title", {}, 5))
  end)

  it("keeps the count when shortening", function()
    assert.equals("lon… (x3)", base.fit_title("long title", dupes, 9))
  end)

  it("uses the given format", function()
    assert.equals("lon… x3", base.fit_title("long title", dupes, 7, "%s x%d"))
  end)
end)

describe("long titles", function()
  local titles = {
    ascii = string.rep("T", 40),
    multibyte = string.rep("é✓", 20),
    wide = string.rep("日本", 20),
  }

  for _, name in ipairs(RENDERERS) do
    for kind, title in pairs(titles) do
      for _, width in ipairs({ 14, 20, 30 }) do
        it(("%s fits a %s title at width %d"):format(name, kind, width), function()
          local texts = draw(name, title, width)
          local joined = table.concat(texts, "")
          assert.is_truthy(joined:find("…", 1, true))
          for _, text in ipairs(texts) do
            assert.is_true(width_of(text) <= width, text)
          end
        end)
      end
    end

    it(name .. " does not change a short title", function()
      local joined = table.concat((draw(name, "Short", 40)), "")
      assert.is_truthy(joined:find("Short", 1, true))
      assert.is_nil(joined:find("…", 1, true))
    end)

    -- wrapped-default falls back to a share of the screen width when there is no max_width.
    if name ~= "wrapped-default" then
      it(name .. " does not shorten without a max_width", function()
        local joined = table.concat((draw(name, titles.ascii, nil)), "")
        assert.is_truthy(joined:find(titles.ascii, 1, true))
        assert.is_nil(joined:find("…", 1, true))
      end)
    end
  end

  it("default leaves room for the time on the same row", function()
    local texts = draw("default", titles.ascii, 30)
    local left, right
    for _, text in ipairs(texts) do
      if text:find("T", 1, true) then
        left = text
      elseif text:find("12:00", 1, true) then
        right = text
      end
    end
    assert.is_true(vim.trim(left):len() > 0)
    local left_used = width_of((left:gsub("%s+$", "")))
    assert.is_true(left_used + width_of(right) <= 30)
  end)

  for _, name in ipairs({ "default", "simple", "inline", "borderless" }) do
    it(name .. " keeps the duplicate count on a shortened title", function()
      local joined = table.concat((draw(name, titles.ascii, 30, { duplicates = { 1, 2 } })), "")
      assert.is_truthy(joined:find("(x2)", 1, true))
      assert.is_truthy(joined:find("…", 1, true))
    end)
  end

  for _, name in ipairs({ "wrapped-default", "wrapped-compact" }) do
    it(name .. " keeps the duplicate count on a shortened title", function()
      local joined = table.concat((draw(name, titles.ascii, 30, { duplicates = { 1, 2 } })), "")
      assert.is_truthy(joined:find("x2", 1, true))
      assert.is_truthy(joined:find("…", 1, true))
    end)
  end

  describe("inline title forms", function()
    local long = titles.ascii

    it("fits a left title", function()
      for _, text in ipairs((draw("inline", { long }, 30))) do
        assert.is_true(width_of(text) <= 30)
      end
    end)

    it("fits a right title", function()
      for _, text in ipairs((draw("inline", { "", long }, 30))) do
        assert.is_true(width_of(text) <= 30)
      end
    end)

    it("fits a split title, sharing the row", function()
      local total = 0
      local texts = draw("inline", { long, long }, 30)
      for _, text in ipairs(texts) do
        local without_bar = text:gsub("━", "")
        total = total + width_of(without_bar)
      end
      assert.is_true(total <= 30)
    end)

    it("keeps a short right title whole beside a long left title", function()
      local joined = table.concat((draw("inline", { long, "right" }, 30)), "")
      assert.is_truthy(joined:find("right", 1, true))
      assert.is_truthy(joined:find("…", 1, true))
    end)
  end)

  describe("compact", function()
    it("shortens the title so the message stays visible", function()
      local _, lines = draw("compact", titles.ascii, 30)
      assert.is_true(width_of(lines[1]) <= 30)
      assert.is_truthy(lines[1]:find(": body$"))
      assert.is_truthy(lines[1]:find("…", 1, true))
    end)

    it("does not change a title that fits", function()
      local _, lines = draw("compact", "Short", 30)
      assert.equals("I | Short: body", lines[1])
    end)

    it("does not shorten without a max_width", function()
      local _, lines = draw("compact", titles.ascii, nil)
      assert.equals("I | " .. titles.ascii .. ": body", lines[1])
    end)

    it("highlights the whole shortened prefix", function()
      local buf = vim.api.nvim_create_buf(false, true)
      render["compact"](
        buf,
        {
          title = { titles.ascii, "" },
          icon = "I",
          level = "INFO",
          message = { "body" },
        },
        HIGHLIGHTS,
        {
          max_width = function()
            return 30
          end,
        }
      )
      local marks = vim.api.nvim_buf_get_extmarks(buf, base.namespace(), 0, -1, { details = true })
      local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      for _, mark in ipairs(marks) do
        if mark[4].hl_group == "Title" then
          local text = line:sub(mark[3] + 1, mark[4].end_col)
          assert.is_truthy(text:find("…", 1, true))
          assert.is_nil(text:find("body", 1, true))
        end
      end
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
