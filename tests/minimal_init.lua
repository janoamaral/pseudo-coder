vim.cmd('filetype plugin indent off')
vim.cmd('syntax off')

vim.opt.runtimepath:append('.')
vim.opt.runtimepath:append('tests')

require('tests.plenary_busted')

require('plenary.test_harness'):setup_busted()
