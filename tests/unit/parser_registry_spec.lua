describe("notify.parsers.registry", function()
  local parsers = require("notify.parsers")
  local registry = parsers.registry
  local lines_dec = require("notify.parsers.decorators.lines")

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

  describe("decorator phase", function()
    it("runs the first matching decorator and records its name in captures", function()
      registry.register_decorator("noop", {
        trigger = function()
          return false
        end,
        format = function()
          return { msg = "noop" }
        end,
      })
      registry.register_decorator("hit", {
        trigger = function(opts)
          return opts.payload and opts.payload.kind == "hit"
        end,
        format = function()
          return { msg = "decorated", highlights = { inline = { { "Comment", 0, 0, 9 } } } }
        end,
      })

      local msg, _, opts = registry.run("orig", "info", { payload = { kind = "hit" } })
      assert.equals("decorated", msg)
      assert.equals("hit", opts.captures.decorator)
      assert.are.same({ { "Comment", 0, 0, 9 } }, opts.highlights.inline)
    end)

    it("stops after the first matching decorator (no pipeline)", function()
      local second_ran = false
      registry.register_decorator("first", {
        trigger = function()
          return true
        end,
        format = function()
          return { msg = "first" }
        end,
      })
      registry.register_decorator("second", {
        trigger = function()
          return true
        end,
        format = function()
          second_ran = true
          return { msg = "second" }
        end,
      })
      local msg, _, opts = registry.run("orig", "info", {})
      assert.equals("first", msg)
      assert.equals("first", opts.captures.decorator)
      assert.is.False(second_ran)
    end)

    it("merges captures returned by the decorator with existing captures", function()
      registry.register_decorator("tag", {
        trigger = function()
          return true
        end,
        format = function()
          return { captures = { tagged = true } }
        end,
      })
      local _, _, opts = registry.run("msg", "info", { captures = { preset = 1 } })
      assert.is.True(opts.captures.tagged)
      assert.equals(1, opts.captures.preset)
      assert.equals("tag", opts.captures.decorator)
    end)
  end)

  describe("matcher phase runs after decorator", function()
    it("populates captures and inline highlights on hit", function()
      registry.register_matcher("err", {
        match = function(msg)
          local file, line = msg:match("^Error at ([^:]+):(%d+)")
          if file then
            return { isError = true, file = file, line = tonumber(line) }
          end
        end,
        highlights = function()
          return { { "NotifyERRORTitle", 0, 0, 5 } }
        end,
      })

      local _, _, opts = registry.run("Error at foo.lua:42", "error", {})
      assert.is.True(opts.captures.isError)
      assert.equals("foo.lua", opts.captures.file)
      assert.equals(42, opts.captures.line)
      assert.equals("err", opts.captures.matcher)
      assert.are.same({ { "NotifyERRORTitle", 0, 0, 5 } }, opts.highlights.inline)
    end)

    it("does nothing when no matcher claims the message", function()
      registry.register_matcher("err", {
        match = function()
          return nil
        end,
      })
      local _, _, opts = registry.run("whatever", "info", {})
      assert.is.Nil(opts.captures)
    end)

    it("runs matcher against the decorator-produced text", function()
      registry.register_decorator("rewrite", {
        trigger = function()
          return true
        end,
        format = function()
          return { msg = "Error at decorated.lua:7" }
        end,
      })
      registry.register_matcher("err", {
        match = function(msg)
          local file = msg:match("^Error at ([^:]+)")
          if file then
            return { file = file }
          end
        end,
      })

      local _, _, opts = registry.run("irrelevant", "error", {})
      assert.equals("decorated.lua", opts.captures.file)
      assert.equals("rewrite", opts.captures.decorator)
      assert.equals("err", opts.captures.matcher)
    end)
  end)

  describe("opts.parser = false", function()
    it("bypasses both decorator and matcher phases", function()
      local dec_ran, match_ran = false, false
      registry.register_decorator("d", {
        trigger = function()
          return true
        end,
        format = function()
          dec_ran = true
          return { msg = "x" }
        end,
      })
      registry.register_matcher("m", {
        match = function()
          match_ran = true
          return { any = true }
        end,
      })

      local msg, _, opts = registry.run("orig", "info", { parser = false })
      assert.equals("orig", msg)
      assert.is.False(dec_ran)
      assert.is.False(match_ran)
      assert.is.Nil(opts.captures)
    end)
  end)

  describe("built-in `lines` decorator", function()
    before_each(function()
      registry.reset()
      lines_dec.register(registry)
    end)

    it("flattens nested-tuple lines into text + inline highlights", function()
      local payload = {
        { { "hello ", "Keyword" }, "world" },
        { { "line two", "String" } },
      }
      local _, _, opts = registry.run("", "info", { payload = { kind = "lines", data = payload } })
      assert.equals("hello world\nline two", (select(
        1,
        registry.run("dummy", "info", {
          payload = { kind = "lines", data = payload },
        })
      )))
      assert.equals("lines", opts.captures.decorator)
      assert.are.same({
        { "Keyword", 0, 0, 6 },
        { "String", 1, 0, 8 },
      }, opts.highlights.inline)
    end)

    it("accepts plain strings for lines without highlights", function()
      local _, _, opts = registry.run("", "info", {
        payload = { kind = "lines", data = { "plain one", "plain two" } },
      })
      assert.equals(0, #(opts.highlights and opts.highlights.inline or {}))
      assert.equals(2, opts.captures.lines_count)
    end)

    it("ignores opts.payload with a different kind", function()
      local _, _, opts = registry.run("orig", "info", {
        payload = { kind = "other", data = {} },
      })
      assert.is.Nil(opts.captures)
    end)
  end)

  describe("parse_message() front door", function()
    it("routes string messages through the registry", function()
      local tagged = false
      registry.register_matcher("tag", {
        match = function(msg)
          if msg == "hello" then
            tagged = true
            return { tagged = true }
          end
        end,
      })
      local msg, _, opts = parsers.parse_message("hello", "info", {})
      assert.equals("hello", msg)
      assert.is.True(tagged)
      assert.is.True(opts.captures.tagged)
    end)

    it("still handles legacy table messages and writes inline highlights", function()
      local msg, _, opts = parsers.parse_message({
        { { "hi ", "Keyword" }, { "there", "Comment" } },
      }, "info", {})
      assert.equals("hi there", msg)
      assert.is.Not.Nil(opts.highlights.inline)
      assert.equals(2, #opts.highlights.inline)
    end)
  end)
end)
