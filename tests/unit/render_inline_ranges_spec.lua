local base = require("notify.render.base")
local log = require("notify.util.log")
local render = require("notify.render")

local CONFIG = {
  max_width = function()
    return 12
  end,
  minimum_width = function()
    return 3
  end,
}

local HIGHLIGHTS =
  { title = "Title", icon = "Icon", border = "Border", body = "Body", content = {} }

--- Render and return the text under each mark of `group`, in buffer order, plus any logged errors.
local function run(name, notif, group)
  local logged = {}
  local real_error = log.error
  log.error = function(msg)
    table.insert(logged, msg)
  end
  local buf = vim.api.nvim_create_buf(false, true)
  notif = vim.tbl_extend("keep", notif, {
    title = { "", "12:00" },
    icon = "I",
    level = "INFO",
  })
  render[name](buf, notif, HIGHLIGHTS, CONFIG)
  log.error = real_error

  local marks = vim.api.nvim_buf_get_extmarks(buf, base.namespace(), 0, -1, { details = true })
  local text = {}
  for _, mark in ipairs(marks) do
    if mark[4].hl_group == group then
      local end_row, end_col = mark[4].end_row, mark[4].end_col
      -- A body mark may end at the start of the line after the last one.
      local line_count = vim.api.nvim_buf_line_count(buf)
      if end_row >= line_count then
        end_row = line_count - 1
        end_col = #vim.api.nvim_buf_get_lines(buf, end_row, end_row + 1, false)[1]
      end
      local lines = vim.api.nvim_buf_get_text(buf, mark[2], mark[3], end_row, end_col, {})
      table.insert(text, table.concat(lines, "\n"))
    end
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  vim.api.nvim_buf_delete(buf, { force = true })
  return text, logged, lines
end

local function ranges(group, list)
  local inline = {}
  for _, range in ipairs(list) do
    table.insert(inline, { group, range[1], range[2], range[3] })
  end
  return { inline = inline }
end

describe("inline highlight ranges", function()
  describe("unwrapped renderers", function()
    local cases = {
      { name = "default", title = { "T", "12:00" } },
      { name = "simple", title = { "T", "12:00" } },
      { name = "minimal" },
      { name = "compact" },
      { name = "compact", title = { "My Title", "12:00" } },
    }
    for _, case in ipairs(cases) do
      local label = case.name .. (case.title and " with a title" or "")

      it(label .. " highlights the same text on every row", function()
        local text, logged = run(case.name, {
          title = case.title,
          message = { "alpha beta", "gamma", "d" },
          highlights = ranges("Mark", { { 0, 6, 10 }, { 1, 0, 5 }, { 2, 0, 1 } }),
        }, "Mark")
        assert.same({}, logged)
        assert.same({ "beta", "gamma", "d" }, text)
      end)
    end

    it("minimal accounts for the duplicate count prefix", function()
      local text, logged = run("minimal", {
        message = { "alpha beta", "gamma" },
        duplicates = { 1, 2 },
        highlights = ranges("Mark", { { 0, 6, 10 }, { 1, 0, 5 } }),
      }, "Mark")
      assert.same({}, logged)
      assert.same({ "beta", "gamma" }, text)
    end)
  end)

  describe("wrapped renderers", function()
    local cases = {
      { name = "wrapped-default", title = { "T", "12:00" } },
      { name = "wrapped-minimal" },
      { name = "wrapped-compact" },
      { name = "wrapped-compact", title = { "My Title", "12:00" } },
    }
    for _, case in ipairs(cases) do
      local label = case.name .. (case.title and " with a title" or "")

      it(label .. " highlights a range inside one wrapped line", function()
        local text, logged = run(case.name, {
          title = case.title,
          message = { "abcdefgh", "second" },
          highlights = ranges("Mark", { { 0, 2, 5 }, { 1, 0, 6 } }),
        }, "Mark")
        assert.same({}, logged)
        assert.same({ "cde", "second" }, text)
      end)

      it(label .. " splits a range across the lines it wraps onto", function()
        local long = string.rep("a", 15) .. string.rep("b", 15)
        local text, logged = run(case.name, {
          title = case.title,
          message = { long },
          highlights = ranges("Mark", { { 0, 0, #long } }),
        }, "Mark")
        assert.same({}, logged)
        assert.equals(long, table.concat(text))
        assert.is_true(#text > 1)
      end)

      it(label .. " marks only the wrapped line a range falls on", function()
        local long = string.rep("a", 15) .. string.rep("b", 15)
        local text, logged = run(case.name, {
          title = case.title,
          message = { long },
          highlights = ranges("Mark", { { 0, #long - 3, #long } }),
        }, "Mark")
        assert.same({}, logged)
        assert.same({ "bbb" }, text)
      end)

      it(label .. " highlights multibyte text across wrapped lines", function()
        local long = string.rep("✓", 40)
        local text, logged = run(case.name, {
          title = case.title,
          message = { long },
          highlights = ranges("Mark", { { 0, 0, #long } }),
        }, "Mark")
        assert.same({}, logged)
        assert.equals(long, table.concat(text))
        assert.is_true(#text > 1)
      end)

      it(label .. " skips whitespace trimmed by wrapping", function()
        local text, logged = run(case.name, {
          title = case.title,
          message = { "  padded" },
          highlights = ranges("Mark", { { 0, 0, 8 } }),
        }, "Mark")
        assert.same({}, logged)
        assert.same({ "padded" }, text)
      end)
    end
  end)

  describe("custom_wrap() segments", function()
    it("records where each wrapped line came from", function()
      local lines, segments = base.custom_wrap({ "abcdef", " gh" }, 4, { pad_left = ">" })
      assert.same({ ">abcd", ">ef", ">gh" }, lines)
      assert.same({
        { row = 0, start = 0, finish = 4, col = 1 },
        { row = 0, start = 4, finish = 6, col = 1 },
        { row = 1, start = 1, finish = 3, col = 1 },
      }, segments)
    end)
  end)
end)

describe("wrapped-compact", function()
  it("does not run past the title row", function()
    local title, logged, lines = run("wrapped-compact", {
      title = { "My Title", "12:00" },
      message = { "body" },
    }, "Title")
    assert.same({}, logged)
    assert.same({ "My Title" }, vim.tbl_map(vim.trim, title))
    assert.equals(" I My Title", lines[1])
  end)

  it("highlights the body from the row after the title", function()
    local body, logged = run("wrapped-compact", {
      title = { "My Title", "12:00" },
      message = { "body" },
    }, "Body")
    assert.same({}, logged)
    assert.is_true(body[1]:find("^%s*body") ~= nil)
    assert.is_nil(body[1]:find("Title"))
  end)

  it("highlights the body after the prefix when there is no title", function()
    local body, logged, lines = run("wrapped-compact", { message = { "body" } }, "Body")
    assert.same({}, logged)
    assert.equals(" I  body ", lines[1])
    assert.is_nil(body[1]:find("I"))
  end)

  it("renders an empty message without inventing text", function()
    local _, logged, lines = run("wrapped-compact", { message = { "" } }, "Body")
    assert.same({}, logged)
    assert.equals(" I ", lines[1])
  end)
end)

describe("set_extmark() failures", function()
  it("logs the position that failed", function()
    local logged = {}
    local real_error = log.error
    log.error = function(msg)
      table.insert(logged, msg)
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "abc" })
    base.set_extmark(buf, 0, 1, { end_col = 9 })
    log.error = real_error
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.equals(
      "notify render: failed to set extmark at line 0, col 1, end_col 9, line length 3:",
      logged[1]
    )
  end)

  it("logs a line past the end of the buffer", function()
    local logged = {}
    local real_error = log.error
    log.error = function(msg)
      table.insert(logged, msg)
    end
    local buf = vim.api.nvim_create_buf(false, true)
    base.set_extmark(buf, 9, 0, {})
    log.error = real_error
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.is_truthy(logged[1]:find("line 9, col 0, end_col nil, line length none", 1, true))
  end)
end)
