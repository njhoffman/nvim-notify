# nvim-notify: A fork of rcarriga/nvim-notify  

This file should be always referenced before each task, it contains general guidelines and
procedures.  The file `task.md` will contain the current task information, ignore the TODO.md file until told
differently.  

The end goal is to organize my code, cleanup deprecated or unused code, remove errors, refine and
add features in a more procedural way that involve running tests.  

## Important references

Testing resources:
- github.com/nvim-lua/plenary.nvim/blob/master/TESTS_README.md
- github.com/echasnovski/mini.nvim/blob/main/readmes/mini-test.md
- <https://github.com/neovim/neovim/blob/master/test/functional/api/extmark_spec.lua>
- <https://luaunit.readthedocs.io/>

## Architecture and technical requirements
- Error Handling: Comprehensive logging to file with timestamps for all operations
- Testing: Use luaunit for unit tests and neovim for integration tests.  These shouuld be run
    before every update.  Use neovim to run tests in headless mode.
- Version Control: Use git for version control, commit messages following conventional commit format
  with gitmoji.  Project root `package.json` and git tags track version number.
- Documentation: Add necessary documentation for project, including README.md, USAGE.md for cli
  interface, and CHANGELOG.md for version history (automatically generate and update this file
  only when minor or major version bumps occur).

Read the `task.md` file for the next task.
