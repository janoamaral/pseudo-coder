local M = {}

local function ensure_plenary()
  local rtp = vim.opt.runtimepath:get()
  for _, entry in ipairs(rtp) do
    if vim.fn.filereadable(entry .. '/lua/plenary/test_harness/init.lua') == 1 then
      return
    end
  end

  local default_path = vim.fn.stdpath('data') .. '/site/pack/plenary/start/plenary.nvim'
  if vim.fn.isdirectory(default_path) == 0 then
    error('plenary.nvim not found; install it or update tests/plenary_busted.lua')
  end
  vim.opt.runtimepath:append(default_path)
end

function M.setup()
  ensure_plenary()
end

M.setup()

return M
