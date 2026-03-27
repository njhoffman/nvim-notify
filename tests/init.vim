set rtp+=.
set rtp+=../plenary.nvim

" Also check common lazy.nvim and packer paths
let s:lazy_plenary = expand('~/.local/share/nvim/lazy/plenary.nvim')
let s:packer_plenary = expand('~/.local/share/nvim/site/pack/packer/start/plenary.nvim')
if isdirectory(s:lazy_plenary)
  execute 'set rtp+=' . s:lazy_plenary
elseif isdirectory(s:packer_plenary)
  execute 'set rtp+=' . s:packer_plenary
endif

set termguicolors
runtime! plugin/plenary.vim
