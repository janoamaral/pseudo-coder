describe("pseudo-coder", function()
  local plugin

  before_each(function()
    package.loaded["pseudo-coder"] = nil
    plugin = require("pseudo-coder")
  end)

  it("builds prompts with filetype", function()
    local selection = {
      lines = { "foo" },
    }
    local prompt = plugin._test.build_prompt("lua", selection)
    assert.matches("lua", prompt)
    assert.matches("foo", prompt)
  end)

  it("sanitizes markdown fences", function()
    local text = [[```lua
print('hello')
```]]
    local cleaned = plugin._test.sanitize_response(text)
    assert.equals("print('hello')", cleaned)
  end)

  it("merges nested tables", function()
    local defaults = { a = 1, nested = { b = 2, deep = { c = 3 } } }
    local overrides = { nested = { deep = { c = 9 }, d = 4 } }
    local merged = plugin._test.merge_tables(defaults, overrides)
    assert.equals(1, merged.a)
    assert.equals(2, merged.nested.b)
    assert.equals(9, merged.nested.deep.c)
    assert.equals(4, merged.nested.d)
  end)

  it("captures visual selection spans", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "line one",
      "line two",
    })

    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal! vll")
    local selection = plugin._test.capture_selection()
    assert.is_not_nil(selection)
    assert.same({ "li" }, selection.lines)
  end)
end)
