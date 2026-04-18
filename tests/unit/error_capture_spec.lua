-- Error matcher + renderer coverage, driven by the personal error corpus
-- at ~/.config/nvim/lua/notify/_demo/errors.lua when present, plus a
-- baseline set of inline samples so the suite is self-contained.

describe("notify.parsers.matchers.error", function()
  local error_matcher = require("notify.parsers.matchers.error")
  local parse = error_matcher._parse

  local function load_corpus()
    local ok, errors = pcall(dofile, vim.fn.expand("~/.config/nvim/lua/notify/_demo/errors.lua"))
    if ok and type(errors) == "table" then
      return errors
    end
    return {}
  end

  describe("single-line forms", function()
    it("parses `E471: Argument required` (no path)", function()
      local out = parse("E471: Argument required")
      assert.is.Nil(out)
    end)

    it("parses `file:line: message` with no E-code", function()
      local out = parse("scratch/tmp3.lua:32: unexpected symbol near 'local'")
      assert.is.Not.Nil(out)
      assert.is.True(out.isError)
      assert.is.Nil(out.errorCode)
      assert.equals("scratch/tmp3.lua", out.errorFile)
      assert.equals(32, out.errorLine)
      assert.is.truthy(out.errorMessage:find("unexpected symbol"))
    end)

    it("parses `Ecode: file:line: message`", function()
      local out = parse(
        "E5112: Error while creating lua chunk: lua/scripts/notify-test.lua:10: 'end' expected (to close 'function' at line 50) near '<eof>'"
      )
      assert.equals("E5112", out.errorCode)
      assert.equals("lua/scripts/notify-test.lua", out.errorFile)
      assert.equals(10, out.errorLine)
      assert.is.truthy(out.errorMessage:find("expected"))
    end)

    it("ignores plain word:number without a path", function()
      assert.is.Nil(parse("task foo:42 completed"))
    end)

    it("returns nil for nil input", function()
      assert.is.Nil(parse(nil))
    end)
  end)

  describe("multi-line forms with stack traceback", function()
    it("splits a single traceback into one group", function()
      local msg = table.concat({
        "E5108: Error executing lua: /home/nicholas/.config/nvim/lua/funcs/alt-alt.lua:116: Vim:E565: Not allowed to change text or change window",
        "stack traceback:",
        "  [C]: in function 'edit'",
        "  /home/nicholas/.config/nvim/lua/funcs/alt-alt.lua:116: in function 'gotoAltBuffer'",
        "  /home/nicholas/.config/nvim/lua/keymaps.lua:524: in function </home/nicholas/.config/nvim/lua/keymaps.lua:520>",
      }, "\n")
      local out = parse(msg)
      assert.equals("E5108", out.errorCode)
      -- Innermost path:line:message wins (E565 wrapper); title line keeps file.
      assert.equals("/home/nicholas/.config/nvim/lua/funcs/alt-alt.lua", out.errorFile)
      assert.equals(116, out.errorLine)
      assert.equals(1, #out.errorStackgroups)
      assert.equals(3, #out.errorStackgroups[1])
    end)

    it("splits two consecutive tracebacks into two groups", function()
      local msg = table.concat({
        "E5108: Error executing lua vim/_editor.lua:0: nvim_exec2()..function <lambda>6715, line 1: Vim(copen):E5108: Error executing lua scratch/tmp3.lua:17: attempt to compare number with nil",
        "stack traceback:",
        "  scratch/tmp3.lua:17: in function 'format_filename'",
        "  scratch/tmp3.lua:34: in function 'get_max_filename_width'",
        "stack traceback:",
        "  [C]: in function 'nvim_exec2'",
        "  vim/_editor.lua: in function 'cmd'",
      }, "\n")
      local out = parse(msg)
      assert.equals("E5108", out.errorCode)
      assert.equals(2, #out.errorStackgroups)
      assert.equals(2, #out.errorStackgroups[1])
      assert.equals(2, #out.errorStackgroups[2])
      -- Innermost user frame should win over nested wrappers
      assert.equals("scratch/tmp3.lua", out.errorFile)
      assert.equals(17, out.errorLine)
    end)

    it("picks the last path:line: triple in nested wrapper titles", function()
      local msg =
        "Vim(copen):Error executing Lua callback: ./scratch/tmp2.lua:2: attempt to perform arithmetic on global '_sd' (a nil value)"
      local out = parse(msg)
      assert.equals("./scratch/tmp2.lua", out.errorFile)
      assert.equals(2, out.errorLine)
      assert.is.truthy(out.errorMessage:find("arithmetic"))
    end)
  end)

  describe("corpus sweep", function()
    local corpus = load_corpus()

    it("loaded corpus or reported empty", function()
      assert.is.truthy(#corpus >= 0)
    end)

    if #corpus > 0 then
      for i, entry in ipairs(corpus) do
        it(("case %d parses to a structured capture"):format(i), function()
          local msg = entry[1]
          local out = parse(msg)
          if out == nil then
            -- Some corpus entries are intentionally sparse (e.g. `E471:
            -- Argument required` which has no file:line). Skip them.
            assert.is.truthy(
              not msg:match("[%w%._/%-\\]+:%d+:"),
              ("corpus[%d] expected to parse but did not: %s"):format(i, msg)
            )
            return
          end
          assert.is.True(out.isError)
          assert.equals("string", type(out.errorFile))
          assert.equals("number", type(out.errorLine))
          if out.errorStackgroups and #out.errorStackgroups > 0 then
            for _, group in ipairs(out.errorStackgroups) do
              assert.equals("table", type(group))
            end
          end
        end)
      end
    end
  end)
end)

describe("notify.render.error", function()
  local render_error = require("notify.render.error")
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  local function highlights()
    return { body = "Normal", border = "Normal", title = "Normal", icon = "Normal", content = {} }
  end

  local function config()
    return {
      minimum_width = function()
        return 10
      end,
      max_width = function()
        return 100
      end,
    }
  end

  it("renders code + title + file line + stack groups", function()
    local notif = {
      icon = "",
      title = { "", "" },
      message = { "ignored" },
      captures = {
        isError = true,
        errorCode = "E5108",
        errorTitle = "E5108: Error executing lua foo.lua:7: oops",
        errorFile = "foo.lua",
        errorLine = 7,
        errorMessage = "oops",
        errorStackgroups = {
          { "foo.lua:7: in function 'bar'", "foo.lua:3: in main chunk" },
        },
      },
    }
    render_error(bufnr, notif, highlights(), config())
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals("E5108: E5108: Error executing lua foo.lua:7: oops", lines[1])
    assert.equals("foo.lua:7: oops", lines[2])
    assert.equals("  foo.lua:7: in function 'bar'", lines[3])
    assert.equals("  foo.lua:3: in main chunk", lines[4])
  end)

  it("inserts a blank line between multiple stack groups", function()
    local notif = {
      icon = "",
      title = { "", "" },
      message = { "ignored" },
      captures = {
        isError = true,
        errorTitle = "foo.lua:1: boom",
        errorFile = "foo.lua",
        errorLine = 1,
        errorMessage = "boom",
        errorStackgroups = { { "g1 a", "g1 b" }, { "g2 a" } },
      },
    }
    render_error(bufnr, notif, highlights(), config())
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals("foo.lua:1: boom", lines[1])
    assert.equals("foo.lua:1: boom", lines[2])
    assert.equals("  g1 a", lines[3])
    assert.equals("  g1 b", lines[4])
    assert.equals("", lines[5])
    assert.equals("  g2 a", lines[6])
  end)

  it("falls back to the default renderer when captures.isError is absent", function()
    local saved = package.loaded["notify.render.default"]
    local called = false
    package.loaded["notify.render.default"] = function()
      called = true
    end
    render_error(bufnr, {
      icon = "",
      title = { "t", "" },
      message = { "x" },
    }, highlights(), config())
    package.loaded["notify.render.default"] = saved
    assert.is.True(called)
  end)
end)

describe("dispatch picks error renderer when captures.isError is set", function()
  local base = require("notify.render.base")

  it("default ruleset routes isError to 'error'", function()
    local notif = {
      title = { "", "" },
      message = { "anything" },
      captures = { isError = true },
    }
    local cfg = {
      max_width = function()
        return nil
      end,
      compact = function()
        return false
      end,
      render_ruleset = function()
        return nil
      end,
    }
    assert.equals("error", base.pick_renderer(notif, cfg))
  end)

  it("compact ruleset also routes isError to 'error'", function()
    local notif = {
      title = { "", "" },
      message = { "x" },
      captures = { isError = true },
    }
    local cfg = {
      max_width = function()
        return nil
      end,
      compact = function()
        return true
      end,
      render_ruleset = function()
        return nil
      end,
    }
    assert.equals("error", base.pick_renderer(notif, cfg))
  end)
end)
