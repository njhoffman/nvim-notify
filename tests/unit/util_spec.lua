describe("util", function()
  local util = require("notify.util")

  describe("is_callable()", function()
    it("returns true for functions", function()
      assert.is.True(util.is_callable(function() end))
    end)

    it("returns truthy for tables with __call on the table itself", function()
      local callable = { __call = function() end }
      assert.is.truthy(util.is_callable(callable))
    end)

    it("returns falsy for tables with __call only on metatable", function()
      local callable = setmetatable({}, {
        __call = function() end,
      })
      -- Note: is_callable checks obj.__call directly, not the metatable
      assert.is.falsy(util.is_callable(callable))
    end)

    it("returns falsy for strings", function()
      assert.is.falsy(util.is_callable("hello"))
    end)

    it("returns falsy for numbers", function()
      assert.is.falsy(util.is_callable(42))
    end)

    it("returns falsy for plain tables", function()
      assert.is.falsy(util.is_callable({ 1, 2, 3 }))
    end)

    it("returns falsy for nil", function()
      assert.is.falsy(util.is_callable(nil))
    end)
  end)

  describe("pop()", function()
    it("removes key from table and returns value", function()
      local tbl = { a = 1, b = 2 }
      local val = util.pop(tbl, "a")
      assert.equals(1, val)
      assert.is.Nil(tbl.a)
    end)

    it("returns default when key is absent", function()
      local tbl = { a = 1 }
      local val = util.pop(tbl, "missing", 99)
      assert.equals(99, val)
    end)

    it("returns nil default when key is absent and no default given", function()
      local tbl = { a = 1 }
      local val = util.pop(tbl, "missing")
      assert.is.Nil(val)
    end)
  end)

  describe("blend()", function()
    it("returns background color at alpha 0", function()
      local bg = 0x000000
      local fg = 0xFF8040
      assert.equals(bg, util.blend(fg, bg, 0))
    end)

    it("returns foreground color at alpha 1", function()
      local bg = 0x000000
      local fg = 0xFF8040
      assert.equals(fg, util.blend(fg, bg, 1))
    end)

    it("blends colors at alpha 0.5", function()
      local result = util.blend(0xFF0000, 0x000000, 0.5)
      -- Should be approximately 0x800000 (128, 0, 0)
      assert.equals(0x800000, result)
    end)
  end)

  describe("round()", function()
    it("rounds 1.5 up to 2", function()
      assert.equals(2, util.round(1.5))
    end)

    it("rounds 1.4 down to 1", function()
      assert.equals(1, util.round(1.4))
    end)

    it("rounds to specified decimal places", function()
      assert.equals(1.23, util.round(1.234, 2))
    end)

    it("rounds negative numbers", function()
      -- floor(-1.5 + 0.5) = floor(-1) = -1
      assert.equals(-1, util.round(-1.5))
    end)
  end)

  describe("partial()", function()
    it("creates a partially applied function", function()
      local add = function(a, b)
        return a + b
      end
      local add5 = util.partial(add, 5)
      assert.equals(8, add5(3))
    end)

    it("works with multiple pre-applied args", function()
      local concat = function(a, b, c)
        return a .. b .. c
      end
      local prefixed = util.partial(concat, "hello", " ")
      assert.equals("hello world", prefixed("world"))
    end)
  end)

  describe("rgb_to_numbers()", function()
    it("converts hex string to number table", function()
      local result = util.rgb_to_numbers("#FF8000")
      assert.are.same({ 255, 128, 0 }, result)
    end)

    it("handles lowercase hex", function()
      local result = util.rgb_to_numbers("#ff8000")
      assert.are.same({ 255, 128, 0 }, result)
    end)
  end)

  describe("numbers_to_rgb()", function()
    it("converts number table to hex string", function()
      local result = util.numbers_to_rgb({ 255, 128, 0 })
      assert.equals("#FF800", result)
    end)
  end)

  describe("max_line_width()", function()
    it("returns the maximal width of a table of lines", function()
      assert.equals(5, util.max_line_width({ "12", "12345", "123" }))
    end)

    it("returns 0 for nil input", function()
      assert.equals(0, util.max_line_width())
    end)

    it("returns 0 for empty table", function()
      assert.equals(0, util.max_line_width({}))
    end)
  end)

  describe("get_win_config()", function()
    it("returns false for invalid window", function()
      local success, _ = util.get_win_config(99999)
      assert.is.False(success)
    end)
  end)
end)
