describe("notify.render.base", function()
  local base = require("notify.render.base")

  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  local function extmarks()
    return vim.api.nvim_buf_get_extmarks(bufnr, base.namespace(), 0, -1, { details = true })
  end

  describe("namespace()", function()
    it("returns the same integer id on every call", function()
      assert.equals(base.namespace(), base.namespace())
      assert.equals("number", type(base.namespace()))
    end)
  end)

  describe("set_extmark()", function()
    it("creates the extmark on success and returns true", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello world" })
      local ok = base.set_extmark(bufnr, 0, 0, {
        hl_group = "Comment",
        end_col = 5,
        priority = 50,
      })
      assert.is.True(ok)
      assert.equals(1, #extmarks())
    end)

    it("returns false and does not throw on invalid input", function()
      local saved_error = require("notify.util.log").error
      local logged = {}
      require("notify.util.log").error = function(msg, _)
        logged[#logged + 1] = msg
      end
      local ok = base.set_extmark(bufnr, 9999, 0, { hl_group = "Comment" })
      require("notify.util.log").error = saved_error

      assert.is.False(ok)
      assert.is.truthy(#logged > 0)
      assert.equals(0, #extmarks())
    end)
  end)

  describe("highlight_body()", function()
    it("uses buf_highlights.body by default", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa", "bbb" })
      base.highlight_body(bufnr, { body = "Comment" }, {}, 0, 0, 2, 0)
      local marks = extmarks()
      assert.equals(1, #marks)
      assert.equals("Comment", marks[1][4].hl_group)
    end)

    it("honours notif.body_hl_group override", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
      base.highlight_body(
        bufnr,
        { body = "Normal", content = "String" },
        { body_hl_group = "content" },
        0,
        0,
        1,
        0
      )
      local marks = extmarks()
      assert.equals("String", marks[1][4].hl_group)
    end)

    it("falls back to buf_highlights.body when the override key is missing", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
      base.highlight_body(bufnr, { body = "Normal" }, { body_hl_group = "nope" }, 0, 0, 1, 0)
      local marks = extmarks()
      assert.equals("Normal", marks[1][4].hl_group)
    end)

    it("omits end_col when none is passed", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "aaa" })
      base.highlight_body(bufnr, { body = "Normal" }, {}, 0, 0, 1)
      local marks = extmarks()
      assert.equals(1, #marks)
    end)
  end)

  describe("highlight_inline()", function()
    local function inline_notif(entries)
      return { highlights = { inline = entries } }
    end

    it("is a no-op when notif has no inline highlights", function()
      base.highlight_inline(bufnr, { content = {} }, {}, 0, 0)
      assert.equals(0, #extmarks())
    end)

    it("applies each inline entry at the offset start_line + row, start_col + col", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "line zero", "line one" })
      local buf_highlights = {
        content = {
          ["Comment"] = "Comment",
          ["String"] = "String",
        },
      }
      local notif = inline_notif({
        { "Comment", 0, 0, 4 },
        { "String", 1, 5, 8 },
      })
      base.highlight_inline(bufnr, buf_highlights, notif, 0, 0)

      local marks = extmarks()
      assert.equals(2, #marks)
      local by_group = {}
      for _, m in ipairs(marks) do
        by_group[m[4].hl_group] = { row = m[2], col = m[3], end_col = m[4].end_col }
      end
      assert.are.same({ row = 0, col = 0, end_col = 4 }, by_group.Comment)
      assert.are.same({ row = 1, col = 5, end_col = 8 }, by_group.String)
    end)

    it("honours a non-zero start offset", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "", "xxxhello" })
      local notif = inline_notif({ { "Comment", 0, 0, 5 } })
      base.highlight_inline(bufnr, { content = { Comment = "Comment" } }, notif, 1, 3)
      local marks = extmarks()
      assert.equals(1, #marks)
      assert.equals(1, marks[1][2])
      assert.equals(3, marks[1][3])
      assert.equals(8, marks[1][4].end_col)
    end)

    it("falls back to the raw group name when buf_highlights.content is missing it", function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello" })
      local notif = inline_notif({ { "Comment", 0, 0, 5 } })
      base.highlight_inline(bufnr, {}, notif, 0, 0)
      local marks = extmarks()
      assert.equals(1, #marks)
      assert.equals("Comment", marks[1][4].hl_group)
    end)
  end)

  describe("apply_duplicates()", function()
    it("returns the title unchanged when there are no duplicates", function()
      assert.equals("Error", base.apply_duplicates("Error", {}))
      assert.equals("Error", base.apply_duplicates("Error", { duplicates = {} }))
    end)

    it("appends `(xN)` by default", function()
      assert.equals("Error (x3)", base.apply_duplicates("Error", { duplicates = { 1, 2, 3 } }))
    end)

    it("respects a custom format string", function()
      assert.equals(
        "Error x3",
        base.apply_duplicates("Error", { duplicates = { 1, 2, 3 } }, "%s x%d")
      )
    end)
  end)

  describe("split_length()", function()
    it("splits a string into chunks of the given width", function()
      assert.are.same({ "ab", "cd", "e" }, base.split_length("abcde", 2))
    end)

    it("returns an empty list for an empty string", function()
      assert.are.same({}, base.split_length("", 5))
    end)

    it("returns empty list for non-positive width", function()
      assert.are.same({}, base.split_length("abc", 0))
    end)
  end)

  describe("custom_wrap()", function()
    it("wraps lines to max_width and trims interior whitespace", function()
      local out = base.custom_wrap({ "aaaaaaaa", "bb" }, 4)
      assert.are.same({ "aaaa", "aaaa", "bb" }, out)
    end)

    it("applies pad_left / pad_right", function()
      local out = base.custom_wrap({ "hello" }, 5, { pad_left = ">", pad_right = "<<" })
      assert.are.same({ ">hel<<", ">lo<<" }, out)
    end)
  end)

  describe("dispatch + ruleset registry", function()
    local function make_config(overrides)
      overrides = overrides or {}
      local cfg = {}
      function cfg.max_width()
        return overrides.max_width
      end
      function cfg.compact()
        return overrides.compact
      end
      function cfg.render_ruleset()
        return overrides.render_ruleset
      end
      return cfg
    end

    local function make_notif(overrides)
      overrides = overrides or {}
      return {
        title = { overrides.title or "", overrides.right_title or "" },
        message = overrides.message or { "one line" },
        icon = overrides.icon or "*",
      }
    end

    local saved_ruleset
    before_each(function()
      saved_ruleset = vim.deepcopy(base.get_ruleset("default"))
    end)
    after_each(function()
      base.register_ruleset("default", saved_ruleset)
    end)

    describe("needs_wrap()", function()
      it("returns false when config has no max_width", function()
        assert.is.False(base.needs_wrap(make_notif(), make_config()))
      end)

      it("returns true when any message line exceeds max_width", function()
        local cfg = make_config({ max_width = 5 })
        local notif = make_notif({ message = { "short", "much longer line" } })
        assert.is.True(base.needs_wrap(notif, cfg))
      end)

      it("returns false when every line fits", function()
        local cfg = make_config({ max_width = 20 })
        local notif = make_notif({ message = { "short" } })
        assert.is.False(base.needs_wrap(notif, cfg))
      end)
    end)

    describe("resolve_ruleset()", function()
      it("returns 'default' when nothing is set", function()
        assert.equals("default", base.resolve_ruleset(make_config()))
      end)

      it("returns 'compact' when config.compact is true", function()
        assert.equals("compact", base.resolve_ruleset(make_config({ compact = true })))
      end)

      it("honours an explicit render_ruleset over compact", function()
        assert.equals(
          "custom",
          base.resolve_ruleset(make_config({ compact = true, render_ruleset = "custom" }))
        )
      end)
    end)

    describe("pick_renderer() with the default ruleset", function()
      it("picks minimal for no title and a single line", function()
        assert.equals("minimal", base.pick_renderer(make_notif(), make_config()))
      end)

      it("picks wrapped-minimal for no title and multiple lines", function()
        local notif = make_notif({ message = { "a", "b" } })
        assert.equals("wrapped-minimal", base.pick_renderer(notif, make_config()))
      end)

      it("picks wrapped-default when a title exists and body wraps", function()
        local cfg = make_config({ max_width = 5 })
        local notif = make_notif({ title = "T", message = { "long line that wraps" } })
        assert.equals("wrapped-default", base.pick_renderer(notif, cfg))
      end)

      it("picks default when a title exists and body fits", function()
        local cfg = make_config({ max_width = 100 })
        local notif = make_notif({ title = "T", message = { "short" } })
        assert.equals("default", base.pick_renderer(notif, cfg))
      end)
    end)

    describe("pick_renderer() with the compact ruleset", function()
      it("picks compact when body fits", function()
        local cfg = make_config({ max_width = 100, compact = true })
        local notif = make_notif({ title = "T", message = { "short" } })
        assert.equals("compact", base.pick_renderer(notif, cfg))
      end)

      it("picks wrapped-compact when body wraps", function()
        local cfg = make_config({ max_width = 5, compact = true })
        local notif = make_notif({ title = "T", message = { "long line that wraps" } })
        assert.equals("wrapped-compact", base.pick_renderer(notif, cfg))
      end)
    end)

    describe("registration API", function()
      it("rulesets() lists built-in ruleset names", function()
        local names = base.rulesets()
        assert.is.truthy(vim.tbl_contains(names, "default"))
        assert.is.truthy(vim.tbl_contains(names, "compact"))
      end)

      it("register_ruleset() can add a new named ruleset", function()
        base.register_ruleset("mine", { { pick = "minimal" } })
        local cfg = make_config({ render_ruleset = "mine" })
        assert.equals("minimal", base.pick_renderer(make_notif({ title = "T" }), cfg))
        base.register_ruleset("mine", nil)
      end)

      it("add_rule() prepends by default so custom rules win", function()
        base.add_rule("default", {
          when = function(notif)
            return notif.icon == "!"
          end,
          pick = "simple",
        })
        local notif = make_notif({ title = "T", icon = "!" })
        assert.equals("simple", base.pick_renderer(notif, make_config()))
      end)

      it("add_rule() with a position inserts at that index", function()
        base.register_ruleset("mine", {
          { pick = "default" },
        })
        base.add_rule("mine", {
          when = function()
            return true
          end,
          pick = "minimal",
        }, 2)
        assert.equals(
          "default",
          base.pick_renderer(
            make_notif(),
            make_config({
              render_ruleset = "mine",
            })
          )
        )
        base.register_ruleset("mine", nil)
      end)
    end)

    describe("dispatch()", function()
      it("delegates to the renderer picked by the rules", function()
        local saved_render = package.loaded["notify.render"]
        local called
        package.loaded["notify.render"] = setmetatable({}, {
          __index = function(_, key)
            return function()
              called = key
            end
          end,
        })
        base.dispatch(0, make_notif(), {}, make_config())
        package.loaded["notify.render"] = saved_render
        assert.equals("minimal", called)
      end)
    end)
  end)

  describe("auto renderer", function()
    it("is resolvable via require('notify.render').auto", function()
      local auto = require("notify.render").auto
      assert.equals("function", type(auto))
      assert.equals(auto, base.dispatch)
    end)
  end)
end)
