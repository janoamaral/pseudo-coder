## pseudo-coder.nvim

`pseudo-coder.nvim` is a Neovim plugin that translates pseudo-code selections into real code using your favorite LLM backend—without blocking the editor or sprinkling markdown fences everywhere.

### Features
- Visual-mode capture for `v`, `V`, and `<C-v>` selections
- Non-blocking requests with a floating spinner near the cursor
- Modular backends: Ollama, Copilot CLI, and OpenCode-compatible APIs
- Prompt enforces raw-code responses for deterministic replacements
- Atomic buffer edits with `undojoin`

### Installation
Use your preferred plugin manager. Example with `lazy.nvim`:

```lua
{
  "janoamaral/pseudo-coder",
  config = function()
    require("pseudo-coder").setup()
  end,
}
```

### Configuration

```lua
require("pseudo-coder").setup({
  backend = "ollama", -- "ollama" | "copilot" | "opencode"
  temperature = 0.1,
  max_tokens = 1024,
  backend_config = {
    ollama = { model = "codellama", url = "http://localhost:11434" },
    copilot = { },
    opencode = { url = "http://api.opencode.com/v1", api_key = "sk-...", model = "gpt-4" },
  },
  ui = {
    spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    floating_window = true,
    update_interval = 80,
  },
})
```

### Usage
1. Select pseudo-code in Visual mode.
2. Run `:PseudoCoderTranslate` (map it if you like).
3. The selection is replaced with translated code when the backend responds.

Suggested mapping:

```lua
vim.keymap.set("v", "<leader>tt", require("pseudo-coder").translate_selection, { desc = "Translate pseudo-code" })
```

### Backends
- **Ollama**: requires a running Ollama server; plugin streams partial responses and concatenates them.
- **Copilot CLI**: uses `gh copilot suggest -t code`; ensure `gh auth login` and CLI access.
- **OpenCode**: any OpenAI-compatible endpoint; provide `url`, `model`, and `api_key` if needed.

### Error Handling
- Markdown fences or surrounding whitespace are stripped before insertion.
- Failures surface via `vim.notify` and spinner windows close automatically.

### Testing
Tests are handled via `busted` under `tests/`; run `make test` once tests are added.
