" The isolated &rtp below removes any treesitter parsers the user may have
" installed. Neovim's built-in ftplugins (e.g. ftplugin/lua.lua) call
" vim.treesitter.start() unconditionally and error when no parser is found,
" which cascades into spurious async test timeouts. No-op the starter so
" filetype plugins stay functional without needing parsers in scope.
lua <<EOF
if vim.treesitter and vim.treesitter.start then
  vim.treesitter.start = function() end
end
EOF

" Reset &rtp so the user's ~/.config/nvim can't shadow project modules via
" runtime-path precedence. Include only: project, plenary, nvim runtime.
let s:plenary_paths = []
let s:lazy_plenary = expand('~/.local/share/nvim/lazy/plenary.nvim')
let s:packer_plenary = expand('~/.local/share/nvim/site/pack/packer/start/plenary.nvim')
let s:sibling_plenary = '../plenary.nvim'
if isdirectory(s:lazy_plenary)
  call add(s:plenary_paths, s:lazy_plenary)
elseif isdirectory(s:packer_plenary)
  call add(s:plenary_paths, s:packer_plenary)
elseif isdirectory(s:sibling_plenary)
  call add(s:plenary_paths, s:sibling_plenary)
endif

let &runtimepath = '.,' . join(s:plenary_paths, ',') . ',' . $VIMRUNTIME
let &packpath = &runtimepath

set termguicolors
runtime! plugin/plenary.vim
