describe("notify.render.borderless", function()
  local base = require("notify.render.base")
  local borderless = require("notify.render.borderless")

  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

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

  local function chunks_contain(extmark, text)
    local virt = extmark[4].virt_text or {}
    for _, chunk in ipairs(virt) do
      if chunk[1] and chunk[1]:find(text, 1, true) then
        return true
      end
    end
    return false
  end

  it("renders message verbatim with icon and title decorations", function()
    local notif = make_notif({ title_input = "Hello", message = { "world" } })
    borderless(bufnr, notif, highlights)
    assert.are.same({ "world" }, lines())

    local has_icon, has_title = false, false
    for _, m in ipairs(marks()) do
      if m[4].virt_text_pos == "inline" and m[2] == 0 and chunks_contain(m, "*") then
        has_icon = true
      end
      if m[4].virt_text_pos == "right_align" and chunks_contain(m, "Hello") then
        has_title = true
      end
    end
    assert.is.True(has_icon)
    assert.is.True(has_title)
  end)

  it("honors single-element table title verbatim (no timestamp)", function()
    local notif = make_notif({ title_input = { "T" }, message = { "x" } })
    borderless(bufnr, notif, highlights)
    local found = false
    for _, m in ipairs(marks()) do
      if m[4].virt_text_pos == "right_align" then
        for _, chunk in ipairs(m[4].virt_text) do
          assert.is.Nil(chunk[1]:match("%d%d:%d%d"))
          if chunk[1] == "T" then
            found = true
          end
        end
      end
    end
    assert.is.True(found)
  end)

  it("ignores empty-first table title (only [1] is honored)", function()
    local notif = make_notif({ title_input = { "", "right" }, message = { "x" } })
    borderless(bufnr, notif, highlights)
    for _, m in ipairs(marks()) do
      assert.are_not.equals("right_align", m[4].virt_text_pos)
    end
  end)

  it("omits icon extmark when icon is empty", function()
    local notif = make_notif({ icon = "", title_input = "T", message = { "x" } })
    borderless(bufnr, notif, highlights)
    for _, m in ipairs(marks()) do
      if m[4].virt_text_pos == "inline" and m[2] == 0 then
        for _, chunk in ipairs(m[4].virt_text) do
          assert.are_not.equals("HI", chunk[2])
        end
      end
    end
  end)

  it("multi-line messages get continuation-line padding", function()
    local notif = make_notif({
      icon = "I",
      title_input = "T",
      message = { "first", "second", "third" },
    })
    borderless(bufnr, notif, highlights)
    local pad_count = 0
    for _, m in ipairs(marks()) do
      if m[2] >= 1 and m[4].virt_text_pos == "inline" then
        pad_count = pad_count + 1
      end
    end
    assert.equals(2, pad_count)
  end)

  it("appends (xN) to title with duplicates", function()
    local notif = make_notif({
      title_input = "T",
      duplicates = { 1, 2, 3 },
      message = { "x" },
    })
    borderless(bufnr, notif, highlights)
    local found = false
    for _, m in ipairs(marks()) do
      if m[4].virt_text_pos == "right_align" and chunks_contain(m, "T (x3)") then
        found = true
      end
    end
    assert.is.True(found)
  end)

  it("applies inline highlights at row 0", function()
    local notif = make_notif({
      title_input = "T",
      message = { "abcdef" },
      highlights = { inline = { { "Comment", 0, 0, 3 } } },
    })
    borderless(bufnr, notif, highlights)
    local found = false
    for _, m in ipairs(marks()) do
      if m[2] == 0 and m[4].hl_group == "Comment" then
        found = true
      end
    end
    assert.is.True(found)
  end)

  it("applies body highlight across all message rows", function()
    local notif = make_notif({
      title_input = "T",
      message = { "a", "b", "c" },
    })
    borderless(bufnr, notif, highlights)
    local body_mark
    for _, m in ipairs(marks()) do
      if m[4].hl_group == "HBO" then
        body_mark = m
      end
    end
    assert.is.truthy(body_mark)
    assert.equals(2, body_mark[4].end_row)
  end)
end)
