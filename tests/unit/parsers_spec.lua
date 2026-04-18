describe("parsers", function()
  local parsers = require("notify.parsers")

  describe("parse_message()", function()
    it("passes through plain strings", function()
      local msg, opts = parsers.parse_message("hello world", "info", {})
      assert.equals("hello world", msg)
    end)

    it("returns empty string for nil message", function()
      local msg, _, _ = parsers.parse_message(nil, "info", {})
      assert.equals("", msg)
    end)

    it("joins list of strings with newline", function()
      local msg, opts = parsers.parse_message({ "line1", "line2", "line3" }, "info", {})
      assert.equals("line1\nline2\nline3", msg)
    end)

    it("inspects dict-like tables", function()
      local input = { key = "value" }
      local msg, level, opts = parsers.parse_message(input, "info", {})
      assert.equals(vim.inspect(input), msg)
      assert.equals("info", level)
    end)

    it("extracts embedded highlight tables", function()
      local input = {
        { { "hello ", "Keyword" }, { "world", "Comment" } },
      }
      local msg, level, opts = parsers.parse_message(input, "info", {})
      assert.equals("hello world", msg)
      assert.equals("info", level)
      assert.is.Not.Nil(opts.highlights)
      assert.is.Not.Nil(opts.highlights.inline)
      assert.equals(2, #opts.highlights.inline)
    end)
  end)

  describe("default_formatter()", function()
    it("passes through plain strings", function()
      local msg, level, opts = parsers.default_formatter("hello", "info", {})
      assert.equals("hello", msg)
      assert.equals("info", level)
    end)

    it("joins list tables with newline", function()
      local msg, _, _ = parsers.default_formatter({ "a", "b" }, "info", {})
      assert.equals("a\nb", msg)
    end)

    it("inspects dict tables", function()
      local input = { key = "value" }
      local msg, _, _ = parsers.default_formatter(input, "info", {})
      assert.equals(vim.inspect(input), msg)
    end)
  end)
end)
