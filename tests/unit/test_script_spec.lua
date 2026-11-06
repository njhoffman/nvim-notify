-- Runs scripts/test against a stand-in nvim that prints canned output, because a real failing spec
-- would fail this suite too.
local script = vim.fn.fnamemodify("scripts/test", ":p")

local function write(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines, path)
end

local function summary(failed, errors, success)
  return {
    "Success: \t" .. (success or 3) .. "\t",
    "Failed : \t" .. (failed or 0) .. "\t",
    "Errors : \t" .. (errors or 0) .. "\t",
  }
end

describe("scripts/test", function()
  local dir

  before_each(function()
    dir = vim.fn.tempname()
    write(dir .. "/tests/unit/one_spec.lua", {})
    write(dir .. "/tests/unit/two_spec.lua", {})
    write(dir .. "/tests/unit/helper.lua", {})
    vim.fn.mkdir(dir .. "/tmp", "p")
    write(dir .. "/bin/nvim", {
      "#!/bin/bash",
      'ls -A > "$FAKE_LISTING"',
      'echo "$XDG_STATE_HOME" > "$FAKE_LISTING.state"',
      'touch "$XDG_STATE_HOME/nvim-notify.log"',
      'cat "$FAKE_OUTPUT"',
      'exit "${FAKE_STATUS:-0}"',
    })
    vim.fn.setfperm(dir .. "/bin/nvim", "rwxr-xr-x")
  end)

  after_each(function()
    vim.fn.delete(dir, "rf")
    vim.fn.delete(dir .. ".listing")
    vim.fn.delete(dir .. ".listing.state")
  end)

  --- Run the script in the temp project. Returns its exit status and output.
  local function run(lines, opts)
    opts = opts or {}
    write(dir .. "/output", lines)
    local command = {
      "bash",
      "-c",
      'cd "$1" && shift && exec "$@"',
      "_",
      dir,
      "env",
      "-u",
      "XDG_STATE_HOME",
      "PATH=" .. dir .. "/bin:" .. vim.env.PATH,
      "FAKE_OUTPUT=" .. dir .. "/output",
      "FAKE_STATUS=" .. (opts.status or 0),
      "FAKE_LISTING=" .. dir .. "/../" .. vim.fn.fnamemodify(dir, ":t") .. ".listing",
      "TMPDIR=" .. dir .. "/tmp",
      "bash",
      script,
    }
    if opts.target then
      table.insert(command, opts.target)
    end
    local output = vim.fn.system(command)
    return vim.v.shell_error, output
  end

  local function two_clean()
    return vim.list_extend(summary(), summary())
  end

  it("passes when every spec file reports no failures", function()
    local status = run(two_clean())
    assert.equals(0, status)
  end)

  for _, count in ipairs({ 1, 9, 10, 20, 100, 101 }) do
    it("fails with " .. count .. " failed tests", function()
      local status = run(vim.list_extend(summary(), summary(count)))
      assert.equals(1, status)
    end)

    it("fails with " .. count .. " errors", function()
      local status = run(vim.list_extend(summary(), summary(0, count)))
      assert.equals(1, status)
    end)
  end

  it("passes when a passing count contains a zero", function()
    local status = run(vim.list_extend(summary(0, 0, 10), summary(0, 0, 100)))
    assert.equals(0, status)
  end)

  it("reads summaries wrapped in colour codes", function()
    local red, reset = "\27[31m", "\27[0m"
    local status = run({
      "Success: \t3\t",
      "Failed : \t" .. red .. "10" .. reset .. "\t",
      "Errors : \t0\t",
      "Success: \t3\t",
      "Failed : \t0\t",
      "Errors : \t0\t",
    })
    assert.equals(1, status)
  end)

  it("fails when a spec file's summary is missing", function()
    local status, output = run(summary())
    assert.equals(1, status)
    assert.is_truthy(output:find("1 of 2 spec files", 1, true))
  end)

  it("fails on a failed test whose summary was lost", function()
    local lines = two_clean()
    table.insert(lines, "Fail\t||\tsomething broke\t")
    local status = run(lines)
    assert.equals(1, status)
  end)

  it("does not treat a passing test named after a failure as one", function()
    local lines = two_clean()
    table.insert(lines, "Success\t||\tFail || is only text here\t")
    local status = run(lines)
    assert.equals(0, status)
  end)

  it("fails when nvim exits with an error", function()
    local status, output = run(two_clean(), { status = 3 })
    assert.equals(1, status)
    assert.is_truthy(output:find("status 3", 1, true))
  end)

  it("fails when there are no spec files", function()
    local status, output = run({}, { target = "tests/unit/helper.lua" })
    assert.equals(1, status)
    assert.is_truthy(output:find("no spec files", 1, true))
  end)

  it("expects one summary when given a single spec file", function()
    local status = run(summary(), { target = "tests/unit/one_spec.lua" })
    assert.equals(0, status)
  end)

  it("handles output that is not valid UTF-8", function()
    local lines = two_clean()
    table.insert(lines, "Success\t||\tbroken \255 bytes\t")
    local status = run(lines)
    assert.equals(0, status)
    lines = vim.list_extend(summary(), summary(10))
    table.insert(lines, "Success\t||\tbroken \255 bytes\t")
    status = run(lines)
    assert.equals(1, status)
  end)

  it("shows the test output", function()
    local lines = two_clean()
    table.insert(lines, "visible line")
    local _, output = run(lines)
    assert.is_truthy(output:find("visible line", 1, true))
  end)

  it("keeps its temporary file out of the project while running", function()
    run(two_clean())
    local entries = vim.fn.readfile(dir .. ".listing")
    table.sort(entries)
    assert.same({ "bin", "output", "tests", "tmp" }, entries)
  end)

  it("sends the log to a temporary state directory", function()
    run(two_clean())
    local state = vim.fn.readfile(dir .. ".listing.state")[1]
    assert.is_truthy(vim.startswith(state, dir .. "/tmp/"))
  end)

  it("removes its temporary file", function()
    run(two_clean())
    assert.same({}, vim.fn.readdir(dir .. "/tmp"))
  end)

  it("removes its temporary file when tests fail", function()
    run(summary(1))
    assert.same({}, vim.fn.readdir(dir .. "/tmp"))
  end)

  it("leaves no files behind in the project", function()
    run(two_clean())
    local entries = vim.fn.readdir(dir)
    table.sort(entries)
    assert.same({ "bin", "output", "tests", "tmp" }, entries)
  end)
end)
