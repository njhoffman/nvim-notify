describe("notify.render.inline", function()
  local base = require("notify.render.base")
  local inline = require("notify.render.inline")

  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  local function make_config(min_width)
    return {
      minimum_width = function()
        return min_width or 20
      end,
    }
  end

  local highlights = { icon = "HI", title = "HT", border = "HB", body = "HBO" }

  local function make_notif(overrides)
    overrides = overrides or {}
    return {
      title = overrides.title or { "", "" },
      title_input = overrides.title_input,
      icon = overrides.icon == nil and "*" or overrides.icon,
      message = overrides.message or { "hello world" },
      duplicates = overrides.duplicates,
      highlights = overrides.highlights,
    }
  end

  local function lines()
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end

  local function marks()
    return vim.api.nvim_buf_get_extmarks(bufnr, base.namespace(), 0, -1, { details = true })
  end

  local function find_virt_text(field)
    field = field or "virt_text"
    local out = {}
    for _, m in ipairs(marks()) do
      if m[4][field] then
        table.insert(out, m)
      end
    end
    return out
  end

  local function chunks_contain(extmark, text)
    local virt = extmark[4].virt_text or {}
    for _, chunk in ipairs(virt) do
      if chunk[1] and chunk[1]:find(text, 1, true) then
        return true
      end
    end
    return false
  end

  describe("center mode (string title)", function()
    it("renders header row + body lines", function()
      local notif = make_notif({ title_input = "Hello", message = { "world" } })
      inline(bufnr, notif, highlights, make_config())
      assert.equals(2, #lines())
      assert.equals("", lines()[1])
      assert.equals("world", lines()[2])
    end)

    it("places balanced ━ chunks on both sides of title", function()
      local notif = make_notif({ title_input = "Hi", message = { "msg" } })
      inline(bufnr, notif, highlights, make_config(30))
      local target
      for _, m in ipairs(marks()) do
        if m[2] == 0 and m[4].virt_text_win_col == 0 then
          target = m
          break
        end
      end
      assert.is.truthy(target)
      local virt = target[4].virt_text
      local first = virt[1][1]
      local last = virt[#virt][1]
      assert.is.truthy(first:find("━") ~= nil)
      assert.is.truthy(last:find("━") ~= nil)
    end)

    it("does not include any timestamp text in header", function()
      local notif = make_notif({ title_input = "OnlyTitle", message = { "x" } })
      inline(bufnr, notif, highlights, make_config())
      for _, m in ipairs(marks()) do
        local virt = m[4].virt_text or {}
        for _, chunk in ipairs(virt) do
          assert.is.Nil(chunk[1]:match("%d%d:%d%d:%d%d"))
        end
      end
    end)
  end)

  describe("left mode (single-element table title)", function()
    it("places title at start of header followed by ━", function()
      local notif = make_notif({ title_input = { "Left" }, message = { "msg" } })
      inline(bufnr, notif, highlights, make_config(30))
      local found = false
      for _, m in ipairs(marks()) do
        if m[2] == 0 and m[4].virt_text and m[4].virt_text_win_col == 0 then
          local virt = m[4].virt_text
          local last = virt[#virt][1]
          assert.is.truthy(last:find("━") ~= nil)
          if chunks_contain(m, "Left") then
            found = true
          end
        end
      end
      assert.is.True(found)
    end)

    it("does not emit a right_align extmark", function()
      local notif = make_notif({ title_input = { "Left" }, message = { "msg" } })
      inline(bufnr, notif, highlights, make_config())
      for _, m in ipairs(marks()) do
        assert.are_not.equals("right_align", m[4].virt_text_pos)
      end
    end)
  end)

  describe("right mode (empty-first table title)", function()
    it("emits a right_align extmark with title text", function()
      local notif = make_notif({ title_input = { "", "Right" }, message = { "msg" } })
      inline(bufnr, notif, highlights, make_config())
      local right_marks = {}
      for _, m in ipairs(marks()) do
        if m[4].virt_text_pos == "right_align" then
          table.insert(right_marks, m)
        end
      end
      assert.equals(1, #right_marks)
      assert.is.True(chunks_contain(right_marks[1], "Right"))
    end)

    it("leading extmark contains only ━ filler", function()
      local notif = make_notif({ title_input = { "", "Right" }, message = { "msg" } })
      inline(bufnr, notif, highlights, make_config(30))
      for _, m in ipairs(marks()) do
        if m[4].virt_text_win_col == 0 then
          local virt = m[4].virt_text
          for _, chunk in ipairs(virt) do
            assert.is.Nil(chunk[1]:find("Right", 1, true))
          end
        end
      end
    end)
  end)

  describe("split mode (two-cell table title)", function()
    it("emits left chunks and a right_align extmark", function()
      local notif = make_notif({ title_input = { "Left", "Right" }, message = { "msg" } })
      inline(bufnr, notif, highlights, make_config(40))
      local has_right_align, has_left = false, false
      for _, m in ipairs(marks()) do
        if m[4].virt_text_pos == "right_align" and chunks_contain(m, "Right") then
          has_right_align = true
        elseif m[4].virt_text_win_col == 0 and chunks_contain(m, "Left") then
          has_left = true
        end
      end
      assert.is.True(has_left)
      assert.is.True(has_right_align)
    end)
  end)

  describe("no title (nil)", function()
    it("does not render header row; body starts at row 0", function()
      local notif = make_notif({ title_input = nil, message = { "first", "second" } })
      inline(bufnr, notif, highlights, make_config())
      assert.are.same({ "first", "second" }, lines())
    end)
  end)

  describe("empty title", function()
    it("treats empty string as no title", function()
      local notif = make_notif({ title_input = "", message = { "x" } })
      inline(bufnr, notif, highlights, make_config())
      assert.are.same({ "x" }, lines())
    end)

    it("treats empty table as no title", function()
      local notif = make_notif({ title_input = {}, message = { "x" } })
      inline(bufnr, notif, highlights, make_config())
      assert.are.same({ "x" }, lines())
    end)
  end)

  describe("icon handling", function()
    it("omits icon chunk when icon is empty", function()
      local notif = make_notif({ icon = "", title_input = "Hello", message = { "x" } })
      inline(bufnr, notif, highlights, make_config())
      for _, m in ipairs(marks()) do
        local virt = m[4].virt_text or {}
        for _, chunk in ipairs(virt) do
          assert.are_not.equals("HI", chunk[2])
        end
      end
    end)
  end)

  describe("multi-line message", function()
    it("body spans all message lines", function()
      local notif = make_notif({
        title_input = "T",
        message = { "a", "b", "c", "d", "e" },
      })
      inline(bufnr, notif, highlights, make_config())
      assert.equals(6, #lines())
    end)
  end)

  describe("duplicates", function()
    it("appends (xN) to displayed title in left mode", function()
      local notif = make_notif({
        title_input = { "T" },
        duplicates = { 1, 2 },
        message = { "x" },
      })
      inline(bufnr, notif, highlights, make_config())
      local found = false
      for _, m in ipairs(marks()) do
        if chunks_contain(m, "T (x2)") then
          found = true
          break
        end
      end
      assert.is.True(found)
    end)
  end)

  describe("width clamping", function()
    it("uses minimum_width as a floor", function()
      local notif = make_notif({ title_input = "x", message = { "y" } })
      inline(bufnr, notif, highlights, make_config(50))
      local total_w = 0
      for _, m in ipairs(marks()) do
        if m[4].virt_text_win_col == 0 then
          for _, chunk in ipairs(m[4].virt_text or {}) do
            total_w = total_w + vim.fn.strwidth(chunk[1])
          end
        end
      end
      assert.is.truthy(total_w >= 50 - 2)
    end)
  end)

  describe("inline highlights pass-through", function()
    it("applies inline highlights at body offset", function()
      local notif = make_notif({
        title_input = "T",
        message = { "abcdef" },
        highlights = { inline = { { "Comment", 0, 0, 3 } } },
      })
      inline(bufnr, notif, highlights, make_config())
      local found = false
      for _, m in ipairs(marks()) do
        if m[2] == 1 and m[4].hl_group == "Comment" then
          found = true
        end
      end
      assert.is.True(found)
    end)
  end)
end)
