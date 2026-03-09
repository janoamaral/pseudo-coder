local uv = vim.loop
local api = vim.api

local M = {}

local default_config = {
    backend = "ollama",
    temperature = 0.1,
    max_tokens = 10024,
    backend_config = {
        ollama = { model = "qwen2.5-coder:14b-instruct-q2_K", url = "http://localhost:11434" },
        copilot = {},
        opencode = { url = "http://api.opencode.com/v1", api_key = "", model = "gpt-4" },
    },
    ui = {
        spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
        spinner_icon = "󱚣",
        spinner_label = "translating",
        floating_window = true,
        update_interval = 80,
    },
}

local config = vim.deepcopy(default_config)

local function merge_tables(base, overrides)
    local result = vim.deepcopy(base)
    if type(overrides) ~= "table" then
        return result
    end
    for k, v in pairs(overrides) do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = merge_tables(result[k], v)
        else
            result[k] = v
        end
    end
    return result
end

local function json_decode(payload)
    if payload == nil or payload == "" then
        return nil
    end
    local ok, decoded = pcall(vim.json.decode, payload)
    if ok then
        return decoded
    end
    ok, decoded = pcall(vim.fn.json_decode, payload)
    if ok then
        return decoded
    end
    return nil
end

local function json_encode(tbl)
    local ok, encoded = pcall(vim.json.encode, tbl)
    if ok then
        return encoded
    end
    return vim.fn.json_encode(tbl)
end

local function notify(msg, level)
    level = level or vim.log.levels.INFO
    vim.schedule(function()
        vim.notify("pseudo-coder: " .. msg, level)
    end)
end

local function sanitize_response(text)
    if not text or text == "" then
        return ""
    end
    local cleaned = text:gsub("\r", "")
    cleaned = cleaned:gsub("^```[%w_%-]*%s*", "")
    cleaned = cleaned:gsub("```%s*$", "")
    cleaned = cleaned:gsub("^%s+", "")
    cleaned = cleaned:gsub("%s+$", "")
    return cleaned
end

local function exit_visual_mode()
    local mode = vim.fn.mode()
    if mode:match("^[vV\22]") then
        local esc = api.nvim_replace_termcodes("<Esc>", true, false, true)
        api.nvim_feedkeys(esc, "n", true)
    end
end

local function get_visual_selection()
    local bufnr = vim.api.nvim_get_current_buf()

    -- 1. Get the current mode
    local mode = vim.fn.mode()
    local is_visual = mode:match("^[vV\22]") -- \22 is <C-v> (Visual Block)

    -- 2. Get positions
    -- If we are in visual mode, marks '< and '> are not updated yet.
    -- We must use 'v' (the start of the selection) and '.' (the cursor).
    local start_pos = is_visual and vim.fn.getpos('v') or vim.fn.getpos("'<")
    local end_pos = is_visual and vim.fn.getpos('.') or vim.fn.getpos("'>")

    -- 3. Extract row/col (1-indexed from getpos)
    local start_row, start_col = start_pos[2] - 1, start_pos[3] - 1
    local end_row, end_col = end_pos[2] - 1, end_pos[3] - 1

    -- 4. Normalize: Ensure start is before end
    if start_row > end_row or (start_row == end_row and start_col > end_col) then
        start_row, end_row = end_row, start_row
        start_col, end_col = end_col, start_col
    end

    -- 5. Handle Visual Mode types
    local visual_mode = is_visual and mode or vim.fn.visualmode()

    if visual_mode == "V" then
        -- Line-wise: select the whole start line to the whole end line
        start_col = 0
        local last_line_len = #vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1] or 0
        end_col = last_line_len
    elseif visual_mode == "v" then
        -- Character-wise: nvim_buf_get_text is end-exclusive, so add 1 to end_col
        -- We use math.max to ensure we don't go out of bounds on empty lines
        end_col = end_col + 1
    elseif visual_mode == "\22" then
        -- Visual Block: nvim_buf_get_text doesn't support non-contiguous blocks directly.
        -- This logic gets the "range" encompassing the block.
        end_col = end_col + 1
    end

    -- 6. Safety check for columns (prevents crashes on trailing newline selections)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if end_row >= line_count then end_row = line_count - 1 end

    -- 7. Get the text
    local ok, lines = pcall(vim.api.nvim_buf_get_text, bufnr, start_row, start_col, end_row, end_col, {})

    if not ok or not lines then
        vim.notify("Unable to read visual selection", vim.log.levels.WARN)
        return nil
    end

    return {
        bufnr = bufnr,
        start_row = start_row,
        start_col = start_col,
        end_row = end_row,
        end_col = end_col,
        lines = lines,
        visual_mode = visual_mode,
    }
end

local Spinner = {}
Spinner.__index = Spinner

function Spinner.new()
    if not config.ui.floating_window then
        return nil
    end

    local frames = config.ui.spinner_frames
    if not frames or #frames == 0 then
        frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
    end
    local icon = config.ui.spinner_icon or "󰚩"
    local label = config.ui.spinner_label or "translating"

    local max_frame_width = 1
    for _, frame in ipairs(frames) do
        local width = vim.fn.strdisplaywidth(frame .. " " .. icon .. " " .. label)
        if width > max_frame_width then
            max_frame_width = width
        end
    end

    local height = 1
    local border = "rounded"
    local border_extra = border ~= "none" and 2 or 0
    local padding_bottom = 1
    local padding_right = 2
    local editor_height = math.max(0, (vim.o.lines or 0) - (vim.o.cmdheight or 0))
    local available_bottom = math.max(0, editor_height - 1 - padding_bottom)
    local row = math.max(0, available_bottom - (height + border_extra) + 1)
    local available_right = math.max(0, (vim.o.columns or 0) - 1 - padding_right)
    local col = math.max(0, available_right - (max_frame_width + border_extra) + 1)

    local bufnr = api.nvim_create_buf(false, true)
    local win_id = api.nvim_open_win(bufnr, false, {
        relative = "editor",
        row = row,
        col = col,
        width = max_frame_width,
        height = height,
        style = "minimal",
        border = border,
    })
    local function formatted_frame(idx)
        return frames[idx] .. " " .. icon .. " " .. label
    end

    api.nvim_buf_set_lines(bufnr, 0, -1, false, { formatted_frame(1) })

    local timer = uv.new_timer()
    if not timer then
        api.nvim_win_close(win_id, true)
        api.nvim_buf_delete(bufnr, { force = true })
        return nil
    end

    local index = 1
    timer:start(0, config.ui.update_interval, vim.schedule_wrap(function()
        if not api.nvim_win_is_valid(win_id) then
            timer:stop()
            timer:close()
            return
        end
        api.nvim_buf_set_lines(bufnr, 0, -1, false, { formatted_frame(index) })
        index = (index % #frames) + 1
    end))

    return setmetatable({
        bufnr = bufnr,
        win_id = win_id,
        timer = timer,
    }, Spinner)
end

function Spinner:close()
    if not self then
        return
    end
    if self.timer then
        self.timer:stop()
        self.timer:close()
        self.timer = nil
    end
    if self.win_id and api.nvim_win_is_valid(self.win_id) then
        api.nvim_win_close(self.win_id, true)
    end
    if self.bufnr and api.nvim_buf_is_loaded(self.bufnr) then
        api.nvim_buf_delete(self.bufnr, { force = true })
    end
end

local function build_prompt(filetype, selection)
    local ft = (filetype and filetype ~= "") and filetype or "plain text"
    local body = table.concat(selection.lines, "\n")
    return string.format(
        "Translate this pseudo-code to %s. Return ONLY the raw code. No markdown backticks, no explanations, no preamble. Accuracy is priority.\n\n%s",
        ft,
        body
    )
end

local function apply_result(selection, text)
    local cleaned = sanitize_response(text)
    if cleaned == "" then
        notify("backend returned an empty payload", vim.log.levels.WARN)
        return
    end

    if not api.nvim_buf_is_loaded(selection.bufnr) then
        notify("target buffer is no longer loaded", vim.log.levels.ERROR)
        return
    end

    if not api.nvim_buf_get_option(selection.bufnr, "modifiable") then
        notify("buffer is not modifiable", vim.log.levels.ERROR)
        return
    end

    local ok = pcall(vim.cmd, "undojoin")
    if not ok then
        pcall(vim.cmd, "silent! undojoin")
    end

    local start_row, start_col = selection.start_row, selection.start_col
    local delete_ok, delete_err = pcall(api.nvim_buf_set_text, selection.bufnr, selection.start_row,
        selection.start_col, selection.end_row, selection.end_col, {})
    if not delete_ok then
        notify("failed to clear visual selection: " .. tostring(delete_err), vim.log.levels.ERROR)
        return
    end

    exit_visual_mode()

    local lines = vim.split(cleaned, "\n", { plain = true })
    local insert_ok, insert_err = pcall(api.nvim_buf_set_text, selection.bufnr, start_row, start_col, start_row,
        start_col, lines)
    if not insert_ok then
        notify("failed to insert backend response: " .. tostring(insert_err), vim.log.levels.ERROR)
    end
end

local backend_handlers = {}

backend_handlers.ollama = function(prompt, callback)
    local ollama_cfg = config.backend_config.ollama or {}
    local url = string.format("%s/api/generate", ollama_cfg.url or "http://localhost:11434")
    local payload = json_encode({
        model = ollama_cfg.model or "codellama",
        prompt = prompt,
        stream = false,
    })

    -- Surround payload with single quotes to prevent shell from interpreting
    -- special characters
    payload = payload:gsub("'", "'\\''")

    local args = {
        "curl",
        "-s",
        "-N",
        "-X",
        "POST",
        url,
        "-H",
        "Content-Type: application/json",
        "-d",
        payload,
    }

    -- print full command for debugging (with payload truncated to 100 chars)
    -- print("Running command: " .. table.concat(args, " "):gsub(payload, "'<payload truncated>'"))

    local buffer = ""
    local segments = {}
    local done = false

    local function flush_line(line)
        local decoded = json_decode(line)
        if not decoded then
            return
        end
        if decoded.response then
            table.insert(segments, decoded.response)
        elseif decoded.message and type(decoded.message) == "string" then
            table.insert(segments, decoded.message)
        end
        if decoded.done then
            done = true
        end
    end

    local job_id = vim.fn.jobstart(args, {
        stdout_buffered = false,
        on_stdout = function(_, data)
            -- notify("trace: " .. table.concat(data, "\n"), vim.log.levels.ERROR)
            for _, chunk in ipairs(data or {}) do
                if chunk and chunk ~= "" then
                    buffer = buffer .. chunk
                    while true do
                        local nl = buffer:find("\n")
                        if not nl then
                            break
                        end
                        local line = buffer:sub(1, nl - 1)
                        buffer = buffer:sub(nl + 1)
                        if line ~= "" then
                            flush_line(line)
                        end
                    end
                end
            end
        end,
        on_stderr = function(_, data)
            if data and data[1] and data[1] ~= "" then
                notify("ollama: " .. table.concat(data, "\n"), vim.log.levels.ERROR)
            end
        end,
        on_exit = function(_, code)
            if buffer ~= "" then
                flush_line(buffer)
            end
            if code ~= 0 and #segments == 0 then
                notify("ollama exited with code " .. code, vim.log.levels.ERROR)
                callback(nil)
                return
            end
            callback(table.concat(segments))
        end,
    })

    if job_id <= 0 then
        notify("failed to start curl for Ollama", vim.log.levels.ERROR)
        callback(nil)
    end
end

backend_handlers.copilot = function(prompt, callback)
    local stdout = {}
    local job_id = vim.fn.jobstart({ "gh", "copilot", "suggest", "-t", "code" }, {
        stdout_buffered = false,
        stdin = "pipe",
        on_stdout = function(_, data)
            for _, line in ipairs(data or {}) do
                if line and line ~= "" then
                    table.insert(stdout, line)
                end
            end
        end,
        on_stderr = function(_, data)
            if data and data[1] and data[1] ~= "" then
                notify("copilot: " .. table.concat(data, "\n"), vim.log.levels.ERROR)
            end
        end,
        on_exit = function(_, code)
            if code ~= 0 then
                notify("gh copilot suggest exited with code " .. code, vim.log.levels.ERROR)
                callback(nil)
                return
            end
            callback(table.concat(stdout, "\n"))
        end,
    })

    if job_id <= 0 then
        notify("failed to start gh copilot", vim.log.levels.ERROR)
        callback(nil)
        return
    end

    vim.fn.chansend(job_id, prompt)
    vim.fn.chanclose(job_id, "stdin")
end

backend_handlers.opencode = function(prompt, callback)
    local ocfg = config.backend_config.opencode or {}
    if not ocfg.url or ocfg.url == "" then
        notify("opencode url missing", vim.log.levels.ERROR)
        callback(nil)
        return
    end

    local payload = json_encode({
        model = ocfg.model or "gpt-4",
        temperature = config.temperature,
        max_tokens = config.max_tokens,
        messages = {
            { role = "system", content = "You are a precise code translator." },
            { role = "user",   content = prompt },
        },
    })

    local args = { "curl", "-s", "-X", "POST", string.format("%s/chat/completions", ocfg.url) }
    table.insert(args, "-H")
    table.insert(args, "Content-Type: application/json")
    if ocfg.api_key and ocfg.api_key ~= "" then
        table.insert(args, "-H")
        table.insert(args, "Authorization: Bearer " .. ocfg.api_key)
    end
    table.insert(args, "-d")
    table.insert(args, payload)

    local stdout = {}
    local job_id = vim.fn.jobstart(args, {
        stdout_buffered = true,
        on_stdout = function(_, data)
            if data then
                table.insert(stdout, table.concat(data, "\n"))
            end
        end,
        on_stderr = function(_, data)
            if data and data[1] and data[1] ~= "" then
                notify("opencode: " .. table.concat(data, "\n"), vim.log.levels.ERROR)
            end
        end,
        on_exit = function(_, code)
            if code ~= 0 then
                notify("curl exited with code " .. code, vim.log.levels.ERROR)
                callback(nil)
                return
            end
            local full = table.concat(stdout)
            local decoded = json_decode(full)
            if not decoded or not decoded.choices or not decoded.choices[1] or not decoded.choices[1].message then
                notify("invalid response from opencode", vim.log.levels.ERROR)
                callback(nil)
                return
            end
            callback(decoded.choices[1].message.content)
        end,
    })

    if job_id <= 0 then
        notify("failed to start curl for opencode", vim.log.levels.ERROR)
        callback(nil)
    end
end

local function run_backend(prompt, callback)
    local handler = backend_handlers[config.backend]
    if not handler then
        notify("unknown backend '" .. tostring(config.backend) .. "'", vim.log.levels.ERROR)
        callback(nil)
        return
    end

    handler(prompt, function(result)
        vim.schedule(function()
            callback(result)
        end)
    end)
end

local function translate_selection()
    local selection = get_visual_selection()
    if not selection then
        return
    end

    local ft = vim.bo[selection.bufnr].filetype or ""
    local prompt = build_prompt(ft, selection)

    local spinner = Spinner.new()

    run_backend(prompt, function(result)
        if spinner then
            spinner:close()
        end
        if not result then
            notify("backend returned no result", vim.log.levels.ERROR)
            return
        end
        apply_result(selection, result)
    end)
end

function M.setup(user_config)
    config = merge_tables(default_config, user_config or {})
    api.nvim_create_user_command("PseudoCoderTranslate", translate_selection, { range = true, bar = true })
end

M.translate_selection = translate_selection

M._test = {
    sanitize_response = sanitize_response,
    build_prompt = build_prompt,
    merge_tables = merge_tables,
    capture_selection = get_visual_selection,
}

return M
