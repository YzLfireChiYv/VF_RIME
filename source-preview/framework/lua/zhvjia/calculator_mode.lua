-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- One calculator expression, one real result, one native selection path.
-- Router owns entry conflicts and English-switch guards. This module owns
-- every admitted calculator edit; it never delegates to the legacy editor.
local calc = require("zhvjia/calc")
local M, P, S, T = {}, {}, {}, {}
local ACCEPT, NOOP = 1, 2
local TAG, TYPE = "zhvjia_calculator", "zhvjia_calculator_result"
local DEFAULT_ENTRY = "/="
local SWITCH = { [0xFFE1] = true, [0xFFE2] = true, [0xFFE5] = true }
local DEFAULT_ACTIONS = {
    space = { action = "activate_current" },
    Return = { action = "activate_current" },
    KP_Enter = { action = "activate_current" },
    Tab = { action = "consume_no_action" },
    ["Shift+Tab"] = { action = "consume_no_action" },
    ISO_Left_Tab = { action = "consume_no_action" },
}
local ALIASES = {
    KP_Left = "Left", KP_Right = "Right", KP_Home = "Home",
    KP_End = "End", KP_Delete = "Delete",
}

local function ctx_of(env) return env.engine.context end
local function options(env) return env.calculator_options or {} end
local function entry(env) return options(env).entry or DEFAULT_ENTRY end
local function set_error(ctx, text)
    ctx:set_property("zhvjia_calculator_error", text or "")
end
local function set_prompt(ctx, text)
    if not ctx.composition:empty() then ctx.composition:back().prompt = text or "" end
end

function M.active(ctx, env)
    local lead = env and entry(env) or DEFAULT_ENTRY
    return ctx and type(ctx.input) == "string" and lead ~= "" and
        ctx.input:sub(1, #lead) == lead
end

function M.body(ctx, env)
    return M.active(ctx, env) and ctx.input:sub(#entry(env) + 1) or ""
end

function M.result(env)
    local ctx = ctx_of(env)
    if not M.active(ctx, env) then return nil end
    local expression = M.body(ctx, env)
    if expression == "" then return nil, "请输入算式" end
    local ok, number = pcall(calc.eval, expression)
    if not ok or number == nil then return nil, "算式未完成或无效" end
    local formatted, value = pcall(calc.fmt, number)
    if not formatted or not value or value == "" then
        return nil, "计算结果超出可显示范围"
    end
    return { text = value, expression = expression, input = ctx.input }
end

-- Each raw byte position maps to a valid display UTF-8 boundary. In ordinary
-- use the expression is ASCII; defensive rounding also handles pasted text.
local function display_map(raw, floor, body)
    local map, body_map, boundary = {}, { [0] = 0 }, 0
    for i = 1, #body do
        local next_byte = body:byte(i + 1)
        if not next_byte or next_byte < 128 or next_byte >= 192 then boundary = i end
        body_map[i] = boundary
    end
    for i = 0, #raw do
        map[i + 1] = i <= floor and 0 or body_map[i - floor]
    end
    return map
end

function M.project(env)
    local ctx = ctx_of(env)
    if not M.active(ctx, env) or type(ctx.set_preedit_projection) ~= "function" then
        return false
    end
    local raw, floor = ctx.input, #entry(env)
    local body = raw:sub(floor + 1)
    local map = display_map(raw, floor, body)
    local caret = math.max(floor, math.min(ctx.caret_pos or #raw, #raw))
    local regions = {}
    if body ~= "" then
        regions[1] = {
            start = 0, ["end"] = #body,
            style_key = "calculator.expression", highlightable = true,
        }
    end
    return ctx:set_preedit_projection({
        input_revision = ctx.input_revision, view_revision = ctx.view_revision,
        text = body, raw_to_display = map,
        sel_start = 0, sel_end = map[caret + 1], regions = regions,
    })
end

local function clear_owned_view(ctx, was_active)
    local owns_view = ctx:get_property("_interaction_mode") == "calculator"
    if owns_view then
        ctx:set_property("_interaction_mode", "")
        if type(ctx.clear_preedit_projection) == "function" then
            ctx:clear_preedit_projection()
        end
    end
    if owns_view or was_active then
        ctx:set_property("zhvjia_calculator_input", "")
        set_error(ctx, "")
    end
end

local function own_mode(ctx)
    if ctx:get_property("_interaction_mode") ~= "calculator" then
        ctx:set_property("_interaction_mode", "calculator")
    end
end

local function update(env, ctx)
    if env._calculator_updating then return end
    if not M.active(ctx, env) then
        clear_owned_view(ctx, env._calculator_active)
        env._calculator_active = false
        return
    end
    env._calculator_active = true
    own_mode(ctx)
    local floor = #entry(env)
    if ctx.caret_pos < floor then
        env._calculator_updating = true
        ctx.caret_pos = floor
        env._calculator_updating = false
    end
    M.project(env)
end

function P.init(env)
    if env.calculator_update then return end
    env.calculator_update = ctx_of(env).update_notifier:connect(function(ctx)
        update(env, ctx)
    end)
    update(env, ctx_of(env))
end

function P.fini(env)
    if env.calculator_update then env.calculator_update:disconnect() end
    env.calculator_update, env._calculator_updating = nil, nil
    clear_owned_view(ctx_of(env), env._calculator_active)
    env._calculator_active = nil
end

function S.func(segmentation, env)
    local ctx = ctx_of(env)
    if not M.active(ctx, env) then return true end
    own_mode(ctx)
    -- Compose normally passes only input left of the caret. This expression
    -- owns the complete input, also on an ordinary core without atomic API.
    -- Segmentation.input is a writable binding to Segmentation::Reset.
    segmentation.input = ctx.input
    while not segmentation:empty() do segmentation:pop_back() end
    local seg = Segment(0, #ctx.input)
    seg.tags = seg.tags + Set({ TAG })
    segmentation:add_segment(seg)
    return false
end

function T.func(_, seg, env)
    local ctx = ctx_of(env)
    if not M.active(ctx, env) or not seg:has_tag(TAG) then return end
    own_mode(ctx)
    local result, err = M.result(env)
    set_error(ctx, err)
    -- LuaTranslator receives const Segment&, while Context::back is the
    -- writable native Segment*. Never mutate the Query argument itself.
    set_prompt(ctx, err and ("〔" .. err .. "〕") or "")
    ctx:set_property("zhvjia_calculator_input", "")
    if result then
        local cand = Candidate(TYPE, 0, #result.input, result.text, "")
        cand.quality = 1000000
        -- Original-core fallback hides the entry. Only the native projection
        -- can accurately map a shortened preedit's caret in the middle.
        cand.preedit = result.expression
        local payload = cand
        if type(ctx.make_atomic_candidate) == "function" then
            payload = ctx:make_atomic_candidate(cand)
        end
        if payload then
            ctx:set_property("zhvjia_calculator_input", result.input)
            -- A translator coroutine pauses at yield; do not postpone the
            -- view update until somebody asks for a nonexistent second item.
            M.project(env)
            yield(payload)
        else
            set_error(ctx, "当前算式无法绑定完整结果，请取消后重新输入")
            set_prompt(ctx, "〔无法绑定完整结果〕")
        end
    end
    M.project(env)
end

function M.confirm(env)
    local ctx, raw = ctx_of(env), ctx_of(env).input
    if not M.active(ctx, env) or
        ctx:get_property("zhvjia_calculator_input") ~= raw then return false end
    local candidate = ctx:get_selected_candidate()
    if not candidate or candidate.type ~= TYPE or candidate.start ~= 0 or
        candidate._end ~= #raw or candidate.text == "" then return false end
    local text = candidate.text
    -- This same candidate is also selected by mouse/API. A stale atomic
    -- selection fails in native code; it must never fall back to raw input.
    if not ctx:confirm_current_selection() then return false end
    if ctx.input == "" then return true end
    -- Respect a user's _auto_commit=false without changing the session option.
    -- Explicit confirmation may commit only the fully selected real result.
    if ctx.input == raw and ctx.composition:has_finished_composition() and
        ctx:get_commit_text() == text then
        return ctx:commit()
    end
    return false
end

local function move(ctx, floor, repr)
    local last, caret = #ctx.input, ctx.caret_pos or #ctx.input
    caret = math.max(floor, math.min(caret, last))
    if repr == "Home" then caret = floor
    elseif repr == "End" then caret = last
    elseif repr == "Left" then caret = caret > floor and caret - 1 or last
    elseif repr == "Right" then caret = caret < last and caret + 1 or floor end
    ctx:set_property("zhvjia_last_cursor_key",repr)
    ctx.caret_pos = caret
end

function P.func(key, env)
    local ctx, repr = ctx_of(env), key:repr() or ""
    if not M.active(ctx, env) then return NOOP end
    -- The central router owns switch events and the host fallback. A NOOP
    -- here reports an unhandled event; it must not reopen the legacy chain.
    if SWITCH[key.keycode] then return NOOP end
    if key:release() then return ACCEPT end
    own_mode(ctx)
    local actions = options(env).key_actions
    if actions == nil then actions = DEFAULT_ACTIONS end
    local binding = actions[repr]
    if binding then
        local action = type(binding) == "table" and binding.action or binding
        if action == "activate_current" then M.confirm(env); return ACCEPT
        elseif action == "consume_no_action" then return ACCEPT end
    end
    if repr == "Control+BackSpace" or repr == "Shift+BackSpace" then
        local floor, caret = #entry(env), ctx.caret_pos or #ctx.input
        if caret > floor then ctx:pop_input(caret - floor) end
        M.project(env)
        return ACCEPT
    end
    local replacement=(options(env).input_aliases or {})[repr]
    if replacement then
        if ctx.caret_pos<#entry(env) then ctx.caret_pos=#entry(env) end
        ctx:push_input(replacement)
        return ACCEPT
    end
    if key:ctrl() or key:alt() or key:super() then return NOOP end
    -- Disabling a confirmation binding must not revive legacy commit paths.
    if repr == "space" or repr == "Return" or repr == "KP_Enter" or
        key.keycode == 0xFF09 or key.keycode == 0xFE20 then return ACCEPT end
    if repr == "Escape" then ctx:clear(); clear_owned_view(ctx); return ACCEPT end
    local plain = ALIASES[repr] or repr
    local floor = #entry(env)
    if not key:shift() then
        if plain == "Left" or plain == "Right" or plain == "Home" or plain == "End" then
            move(ctx, floor, plain); M.project(env); return ACCEPT
        end
        if plain == "BackSpace" then
            if ctx.caret_pos > floor then ctx:pop_input(1) end
            return ACCEPT
        end
        if plain == "Delete" then
            if ctx.caret_pos >= floor and ctx.caret_pos < #ctx.input then ctx:delete_input(1) end
            return ACCEPT
        end
    end
    -- A shifted digit key is not an admitted digit. Shift-produced operators
    -- such as '(' are admitted by their actual character, not by stripping
    -- Shift and retrying the unmodified key.
    local code = key.keycode
    local shifted_digit = key:shift() and
        ((code >= 0x30 and code <= 0x39) or (code >= 0xFFB0 and code <= 0xFFB9))
    local char = not shifted_digit and calc.push_char(key) or nil
    if char and char ~= "=" then
        if ctx.caret_pos < floor then ctx.caret_pos = floor end
        ctx:push_input(char)
        return ACCEPT
    end
    return ACCEPT -- no letter, page key or punctuation leaks into old modes
end

M.P, M.S, M.T = P, S, T
return M
