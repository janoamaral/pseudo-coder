local plenary = vim.fn.stdpath('data') .. '/site/pack/plenary/start/plenary.nvim'

if vim.fn.isdirectory(plenary) == 0 then
  error('plenary.nvim not found; clone it or adjust tests/minimal_init.lua')
end

vim.opt.runtimepath:append(plenary)
