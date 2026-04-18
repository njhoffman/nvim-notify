describe("notify.parsers built-ins", function()
  local registry = require("notify.parsers").registry

  local saved_decorators
  local saved_matchers

  before_each(function()
    saved_decorators = {}
    for _, name in ipairs(registry.list_decorators()) do
      saved_decorators[name] = registry.get_decorator(name)
    end
    saved_matchers = {}
    for _, name in ipairs(registry.list_matchers()) do
      saved_matchers[name] = registry.get_matcher(name)
    end
    registry.reset()
  end)

  after_each(function()
    registry.reset()
    for name, spec in pairs(saved_decorators) do
      registry.register_decorator(name, spec)
    end
    for name, spec in pairs(saved_matchers) do
      registry.register_matcher(name, spec)
    end
  end)

  describe("columns decorator", function()
    local columns = require("notify.parsers.decorators.columns")

    before_each(function()
      columns.register(registry)
    end)

    local function run(data)
      return registry.run("", "info", { payload = { kind = "columns", data = data } })
    end

    it("aligns two columns left/right with default padding", function()
      local msg, _, opts = run({
        rows = {
          { "apple", "1" },
          { "banana", "42" },
        },
        columns = {
          { align = "left", highlight = "Keyword" },
          { align = "right", highlight = "Comment" },
        },
      })
      assert.equals("apple   1\nbanana 42", msg)
      assert.equals("columns", opts.captures.layout)
      assert.equals(2, opts.captures.row_count)
      assert.equals(2, opts.captures.column_count)
      assert.are.same({
        { "Keyword", 0, 0, 6 },
        { "Comment", 0, 7, 9 },
        { "Keyword", 1, 0, 6 },
        { "Comment", 1, 7, 9 },
      }, opts.highlights.inline)
    end)

    it("uses the configured separator", function()
      local msg = run({
        rows = { { "a", "b" } },
        separator = " | ",
      })
      assert.equals("a | b", msg)
    end)

    it("respects min_widths when provided", function()
      local msg = run({
        rows = { { "a", "b" } },
        min_widths = { 4, 4 },
      })
      assert.equals("a    b   ", msg)
    end)

    it("skips inline highlights for columns without a highlight group", function()
      local _, _, opts = run({
        rows = { { "a", "b" } },
        columns = { {}, { highlight = "String" } },
      })
      assert.are.same({ { "String", 0, 2, 3 } }, opts.highlights.inline)
    end)

    it("returns empty msg for empty rows but still marks the decorator as run", function()
      local msg, _, opts = run({ rows = {} })
      assert.equals("", msg)
      assert.equals("columns", opts.captures.decorator)
      assert.is.Nil(opts.captures.layout)
    end)

    it("accepts per-cell `{ text, hl_group }` tuples that override column hl", function()
      local _, _, opts = run({
        rows = {
          { "apple", { "1", "Number" } },
          { { "banana", "Identifier" }, "42" },
        },
        columns = {
          { align = "left", highlight = "Keyword" },
          { align = "right", highlight = "Comment" },
        },
      })
      assert.are.same({
        { "Keyword", 0, 0, 6 },
        { "Number", 0, 7, 9 },
        { "Identifier", 1, 0, 6 },
        { "Comment", 1, 7, 9 },
      }, opts.highlights.inline)
    end)

    it("center-aligns when requested", function()
      local msg = run({
        rows = { { "abc", "xxxxxx" } },
        columns = { { align = "center" }, {} },
        min_widths = { 7 },
      })
      assert.equals("  abc   xxxxxx", msg)
    end)
  end)

  describe("error matcher (registry-level)", function()
    local err_matcher = require("notify.parsers.matchers.error")

    before_each(function()
      err_matcher.register(registry)
    end)

    local function run(msg)
      return registry.run(msg, "error", {})
    end

    it("captures isError + file/line/message for a simple file:line: triple", function()
      local _, _, opts = run("Error at foo.lua:42: unexpected symbol")
      assert.is.True(opts.captures.isError)
      assert.equals("foo.lua", opts.captures.errorFile)
      assert.equals(42, opts.captures.errorLine)
      assert.is.truthy(opts.captures.errorMessage:find("unexpected symbol"))
      assert.equals("error", opts.captures.matcher)
    end)

    it("scans multiple lines (not just the first)", function()
      local _, _, opts = run("fine\nbroken.lua:10: bad")
      assert.is.True(opts.captures.isError)
      assert.equals("broken.lua", opts.captures.errorFile)
    end)

    it("ignores plain word:number pairs with no path characters", function()
      local _, _, opts = run("task foo:42 completed")
      assert.is.Nil(opts.captures)
    end)

    it("does not tag non-string messages", function()
      local _, _, opts = registry.run(nil, "info", {})
      assert.is.Nil(opts.captures)
    end)
  end)

  describe("interaction: columns decorator + error matcher", function()
    before_each(function()
      require("notify.parsers.decorators.columns").register(registry)
      require("notify.parsers.matchers.error").register(registry)
    end)

    it("runs decorator first, then matcher scans the decorated output", function()
      local _, _, opts = registry.run("", "info", {
        payload = {
          kind = "columns",
          data = {
            rows = { { "init.lua:12:", "startup failure" } },
            columns = { { highlight = "Keyword" }, { highlight = "Comment" } },
          },
        },
      })
      assert.equals("columns", opts.captures.decorator)
      assert.equals("error", opts.captures.matcher)
      assert.equals("init.lua", opts.captures.errorFile)
      assert.equals(12, opts.captures.errorLine)
    end)
  end)
end)
