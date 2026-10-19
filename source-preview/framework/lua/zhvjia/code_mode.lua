-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- A code session owns one frozen, converted title and one synthesized result.
-- The original spelling is retained only for Escape; it is never retranslated
-- while the suffix is edited. Router/schema integration replaces snippets.P/T.
local snippets = require("zhvjia/snippets")
local M, P, T, S = {}, {}, {}, {}
local ACCEPT, NOOP = 1, 2
local PROP, TITLE = "zhvjia_code_session", "zhvjia_code_title"
local TYPE, TAG = "zhvjia_code_result", "zhvjia_code"
local sessions, serial = {}, 0

local function context(env) return env.engine.context end
local function error_text(ctx, text)
    ctx:set_property("zhvjia_code_error", text or "")
end

local function clear_composition(ctx)
    while not ctx.composition:empty() do ctx.composition:pop_back() end
end

local function copy_segments(ctx)
    local result = {}
    for _, source in ipairs(ctx.composition:toSegmentation():get_segments()) do
        local seg = Segment(source.start, source._end)
        seg.status, seg.tags, seg.menu = source.status, source.tags, source.menu
        seg.selected_index, seg.prompt = source.selected_index, source.prompt
        result[#result + 1] = seg
    end
    return result
end

function M.state(ctx)
    return sessions[ctx:get_property(PROP) or ""]
end

function M.active(ctx)
    local state = M.state(ctx)
    return state ~= nil and (ctx.input or ""):sub(1, #state.prefix) == state.prefix
end

local function forget(ctx)
    sessions[ctx:get_property(PROP) or ""] = nil
    ctx:set_property(PROP, "")
    ctx:set_property(TITLE, "")
    if ctx:get_property("_interaction_mode") == "code" then
        ctx:set_property("_interaction_mode", "")
    end
    if type(ctx.clear_preedit_projection) == "function" then
        ctx:clear_preedit_projection()
    end
end

-- Every byte offset needs a UTF-8 boundary in the native map, even offsets
-- inside a Chinese character that the editor itself can never visit.
local function identity_map(text)
    local map, boundary = { 0 }, 0
    for offset = 1, #text do
        local next_byte = text:byte(offset + 1)
        if not next_byte or next_byte < 128 or next_byte >= 192 then
            boundary = offset
        end
        map[#map + 1] = boundary
    end
    return map
end

function M.project(env)
    local ctx = context(env)
    local state = M.state(ctx)
    if not state or not M.active(ctx) or
        type(ctx.set_preedit_projection) ~= "function" then return false end
    local raw = ctx.input or ""
    local regions = {
        { start = 0, ["end"] = #state.title, style_key = "code.title", highlightable = true },
        { start = #state.title, ["end"] = #state.prefix, style_key = "code.guide", highlightable = false },
    }
    if #raw > #state.prefix then
        regions[#regions + 1] = {
            start = #state.prefix, ["end"] = #raw,
            style_key = "code.suffix", highlightable = false,
        }
    end
    return ctx:set_preedit_projection({
        input_revision = ctx.input_revision, view_revision = ctx.view_revision,
        text = raw, raw_to_display = identity_map(raw),
        sel_start = 0, sel_end = #state.title, regions = regions,
    })
end

-- Read native candidates only, requiring full contiguous coverage. Raw
-- fallbacks and incomplete prefixes are not silently frozen into a title.
local function converted_title(ctx, raw)
    local part = ctx.composition:toSegmentation()
    local pieces, covered = {}, 0
    for _, seg in ipairs(part:get_segments()) do
        if seg.start < #raw and seg._end > seg.start then
            local cand = seg:get_selected_candidate()
            if seg.start ~= covered or not cand or cand.start ~= covered or
                cand._end <= covered or cand._end > #raw or cand.text == "" then
                return nil
            end
            pieces[#pieces + 1], covered = cand.text, cand._end
        end
    end
    if covered ~= #raw then return nil end
    local text = table.concat(pieces)
    return text ~= "" and text or nil
end

-- Router may supply an already captured title. Otherwise the empty auxiliary
-- delimiter is removed internally and Rime composes the complete main input;
-- no Commit/commit_text path is used during this conversion.
function M.enter(env, options)
    local ctx = context(env)
    options = options or {}
    if M.state(ctx) then return false, "代码会话已经存在" end
    local before, caret = ctx.input or "", ctx.caret_pos
    local original_segments = copy_segments(ctx)
    local original = options.raw or before:match("^(.-)`$")
    if not original or original == "" or original:find("`", 1, true) or
        original:sub(1, 1) == "/" then
        return false, "请先清空辅码，再输入第二个反引号"
    end
    local title = options.title
    if title == nil then
        ctx.input = original
        ctx.caret_pos = #original
        env.engine:compose(ctx)
        title = converted_title(ctx, original)
    end
    if type(title) ~= "string" or title == "" or title:find("[\r\n\t`%z]") then
        ctx.input = before
        ctx.caret_pos = math.min(caret or #before, #before)
        env.engine:compose(ctx)
        clear_composition(ctx)
        for _, seg in ipairs(original_segments) do ctx.composition:push_back(seg) end
        return false, "当前主输入尚无覆盖整段的候选，代码标题未转换"
    end
    serial = serial + 1
    local token = tostring(serial)
    local state = {
        title = title, original = original,
        original_caret = math.min(options.caret or caret or #original, #original),
        template_key = options.template_key or original,
        template_label = options.template_label or options.default_template,
        prefix = title .. "``", changing = true,
    }
    sessions[token] = state
    ctx:set_property(PROP, token)
    ctx:set_property(TITLE, title)
    ctx:set_property("_interaction_mode", "code")
    clear_composition(ctx) -- old selected prefixes must not enter atomic output
    ctx.input = state.prefix
    ctx.caret_pos = #state.prefix
    state.changing = false
    env.engine:compose(ctx)
    M.project(env)
    error_text(ctx, "")
    return true
end

function M.leave(env, restore)
    local ctx = context(env)
    local state = M.state(ctx)
    if not state then return false end
    state.changing = true
    forget(ctx)
    clear_composition(ctx)
    if restore then
        ctx.input = state.original
        ctx.caret_pos = state.original_caret
    else
        ctx:clear()
    end
    env.engine:compose(ctx)
    error_text(ctx, "")
    return true
end

-- Suffix grammar is exact: extension[`source[`destination]]. A partially
-- typed identifier is editable, but it cannot produce a misleading payload.
local function parse_suffix(suffix)
    local fields = {}
    for value in (suffix .. "`"):gmatch("(.-)`") do fields[#fields + 1] = value end
    if #fields > 3 then return nil, "代码替换最多接受源、目标两个标识符" end
    if not fields[1]:match("^[a-z][a-z0-9]*$") then
        return nil, fields[1] == "" and "请输入文件后缀，例如 py 或 rs" or "分类使用小写文件后缀"
    end
    for i = 2, #fields do
        if not fields[i]:match("^[A-Za-z_][A-Za-z0-9_]*$") then
            return nil, "请补全替换标识符"
        end
    end
    return { extension = fields[1], source = fields[2], destination = fields[3] }
end

function M.result(env)
    local ctx, state = context(env), M.state(context(env))
    if not state or not M.active(ctx) then return nil end
    local parsed, err = parse_suffix(ctx.input:sub(#state.prefix + 1))
    if not parsed then return nil, err end
    if not snippets.Data then return nil, "代码模板数据接口尚未接入" end
    local item, resolve_error = snippets.Data.exact(state.template_key,
        parsed.extension, state.template_label)
    if not item then return nil, resolve_error end
    local body = snippets.Data.render(item, "space", parsed.source, parsed.destination)
    if not body or body == "" then return nil, "代码模板正文为空" end
    return { body = body, label = item.label or state.title, extension = parsed.extension }
end

function S.func(segmentation, env)
    local ctx = context(env)
    if not M.active(ctx) then return true end
    local raw = ctx.input
    if type(raw) ~= "string" or raw == "" then return false end
    -- Stock Rime's query buffer can end at the caret. This mode has exactly
    -- one whole-input result, including the still editable right-hand suffix.
    if segmentation.input ~= raw then segmentation.input = raw end
    while not segmentation:empty() do segmentation:pop_back() end
    local seg = Segment(0, #raw)
    seg.tags = seg.tags + Set({ TAG })
    segmentation:add_segment(seg)
    return false
end

function T.func(_, seg, env)
    local ctx = context(env)
    if not M.active(ctx) or not seg:has_tag(TAG) then return end
    local result, err = M.result(env)
    error_text(ctx, err)
    M.project(env) -- yield suspends this translator until more candidates are requested
    if result then
        local cand = Candidate(TYPE, 0, #ctx.input, result.body, result.label)
        cand.quality = 1000000
        if type(Interaction) == "table" and type(Interaction.decorate) == "function" then
            -- Top-level decorate accepts source/associated; output is reserved
            -- for attached rows. This standalone item has no child relations.
            cand = Interaction.decorate(cand, {
                kind = "source", label = result.label, style_key = "code.result",
            })
        end
        if type(ctx.make_atomic_candidate) == "function" then
            local atomic = ctx:make_atomic_candidate(cand)
            if atomic then yield(atomic) end
        else
            -- The whole-input segment above gives ordinary Rime the same
            -- concrete commit text without relying on a private extension.
            cand.preedit = ctx.input
            yield(cand)
        end
    end
end

function T.init()
    if snippets.Data then snippets.Data.reload() end
end

local function confirm(env)
    local ctx = context(env)
    local candidate = ctx:get_selected_candidate()
    if candidate and candidate.type == TYPE then
        -- Mouse selection and keyboard confirmation share this real payload.
        ctx:confirm_current_selection()
    end
end

-- An explicit future binding can select a template variant without exposing
-- several competing candidate payloads. Rebinding the same raw bytes advances
-- the input revision, so an older mouse snapshot cannot confirm the old body.
function M.set_variant(env, selection)
    local ctx, state = context(env), M.state(context(env))
    if not state or not M.active(ctx) then return false end
    local parsed = parse_suffix(ctx.input:sub(#state.prefix + 1))
    if not parsed then return false end
    local item = snippets.Data and snippets.Data.exact(state.template_key,
        parsed.extension, selection)
    if not item then return false end
    state.template_label = selection
    local raw, caret = ctx.input, ctx.caret_pos
    ctx.input = raw
    ctx.caret_pos = caret
    env.engine:compose(ctx)
    M.project(env)
    return true
end

local function update(env, c)
    local state = M.state(c)
    if not state or state.changing then return end
    if not c:is_composing() or not M.active(c) then
        forget(c)
        return
    end
    local floor, caret = #state.prefix, c.caret_pos or #c.input
    if caret < floor then
        state.changing = true
        c.caret_pos = floor
        state.changing = false
    end
    M.project(env)
end

function P.init(env)
    local ctx = context(env)
    env.code_update = ctx.update_notifier:connect(function(c) update(env, c) end)
end

function P.fini(env)
    if env.code_update then env.code_update:disconnect(); env.code_update = nil end
    forget(context(env))
end

local function move(ctx, state, key)
    local floor, last, pos = #state.prefix, #ctx.input, ctx.caret_pos or #ctx.input
    if key == "Home" then pos = floor
    elseif key == "End" then pos = last
    elseif key == "Left" then pos = pos > floor and pos - 1 or last
    elseif key == "Right" then pos = pos < last and pos + 1 or floor
    end
    ctx:set_property("zhvjia_last_cursor_key",key)
    ctx.caret_pos = pos
end

local function digit_of(code)
    if code and code >= 0x30 and code <= 0x39 then
        return tostring(code - 0x30), "main"
    end
    if code and code >= 0xFFB0 and code <= 0xFFB9 then
        return tostring(code - 0xFFB0), "keypad"
    end
end

local function literal_digit_enabled(env, keyboard)
    -- The central configuration compiler supplies this immutable option:
    -- code_options.digits.{main,keypad} = "candidate" (default) or "literal".
    -- Missing or unrecognized values never enable additional input characters.
    local options = env.code_options
    local digits = type(options) == "table" and options.digits
    return type(digits) == "table" and digits[keyboard] == "literal"
end

function P.func(key, env)
    local ctx, repr = context(env), key:repr() or ""
    if key:release() then return NOOP end
    if not M.active(ctx) then
        if key:ctrl() or key:alt() or key:super() or key:shift() then return NOOP end
        if key.keycode ~= 0x60 then return NOOP end
        local raw = ctx.input or ""
        if raw ~= "" and ctx.caret_pos==#raw and raw:sub(-1) == "`" and not raw:sub(1, -2):find("`", 1, true) then
            local options = env.code_options or {}
            local _, err = M.enter(env, { default_template = options.default_template })
            if err then error_text(ctx, err) end
            return ACCEPT
        end
        return NOOP
    end
    local state = M.state(ctx)
    if repr == "Escape" then M.leave(env, true); return ACCEPT end
    if repr == "Tab" or repr == "Shift+Tab" or repr == "ISO_Left_Tab" then return ACCEPT end
    if repr == "space" or repr == "Return" or repr == "KP_Enter" then
        confirm(env); return ACCEPT
    end
    local plain = not key:ctrl() and not key:alt() and not key:super() and not key:shift()
    local digit, keyboard = digit_of(key.keycode)
    if digit and not key:ctrl() and not key:alt() and not key:super() then
        if plain then
            if literal_digit_enabled(env, keyboard) then
                ctx:push_input(digit)
            elseif digit == "1" then
                confirm(env)
            end
        end
        return ACCEPT -- Shift digits never select or enter the literal branch
    end
    if repr == "Control+BackSpace" or repr == "Shift+BackSpace" then
        local floor, pos = #state.prefix, ctx.caret_pos or #ctx.input
        local start = floor
        for i = floor + 1, pos do if ctx.input:sub(i, i) == "`" then start = i end end
        if pos > start then ctx:pop_input(pos - start) end
        return ACCEPT
    end
    if key:ctrl() or key:alt() or key:super() then return NOOP end
    local aliases = {
        KP_Left = "Left", KP_Right = "Right", KP_Home = "Home", KP_End = "End",
        KP_Delete = "Delete",
    }
    repr = aliases[repr] or repr
    if repr == "Left" or repr == "Right" or repr == "Home" or repr == "End" then
        move(ctx, state, repr); M.project(env); return ACCEPT
    end
    if repr == "BackSpace" then
        if ctx.caret_pos > #state.prefix then ctx:pop_input(1) end
        return ACCEPT
    end
    if repr == "Delete" then
        if ctx.caret_pos < #ctx.input then ctx:delete_input(1) end
        return ACCEPT
    end
    -- There is exactly one result; paging/navigation cannot change its body.
    local code = key.keycode
    if code and code >= 32 and code < 127 then
        local char = string.char(code)
        if char:match("^[A-Za-z0-9_`]$") then
            ctx:push_input(char); return ACCEPT
        end
    end
    return ACCEPT
end

M.P, M.T, M.S = P, T, S
M.parse_suffix = parse_suffix
return M
