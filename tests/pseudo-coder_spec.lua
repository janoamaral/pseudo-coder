local api = vim.api

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
end)
