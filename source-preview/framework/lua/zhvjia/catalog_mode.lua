-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- Explicit snippet directory. Menu text is the real rendered body, so native
-- mouse selection and keyboard confirmation never disagree about the output.
local snippets = require("zhvjia/snippets")
local M, P, S, T = {}, {}, {}, {}
local ACCEPT, NOOP = 1, 2
local ENTRY, TYPE, TAG = "chapianduan``", "zhvjia_catalog_result", "zhvjia_catalog"

local function context(env) return env.engine.context end
function M.owns(raw)
    return type(raw) == "string" and raw:sub(1, #ENTRY) == ENTRY
end
function M.active(ctx) return M.owns(ctx.input or "") end

local function set_mode(ctx)
    if ctx:get_property("_interaction_mode") ~= "catalog" then
        ctx:set_property("_interaction_mode", "catalog")
    end
end
local function clear_mode(ctx)
    if ctx:get_property("_interaction_mode") == "catalog" then
        ctx:set_property("_interaction_mode", "")
    end
    if type(ctx.clear_preedit_projection) == "function" then
        ctx:clear_preedit_projection()
    end
end

local function parse(raw)
    if not M.owns(raw) then return nil end
    local suffix = raw:sub(#ENTRY + 1)
    local extension, filter = suffix:match("^([a-z][a-z0-9]*)`([A-Za-z_][A-Za-z0-9_]*)$")
    if extension then return extension, filter end
    extension = suffix:match("^([a-z][a-z0-9]*)`$")
    if extension then return extension, "" end
    -- Empty extension intentionally searches all registered template types.
    filter = suffix:match("^`([A-Za-z_][A-Za-z0-9_]*)$")
    if filter then return "", filter end
    if suffix == "`" then return "", "" end
    if suffix == "" or suffix:match("^[a-z][a-z0-9]*$") then return suffix, "" end
    return nil, nil, "请输入精确文件后缀，反引号后可按编码或名称筛选"
end

local function prompt(ctx, text)
    ctx:set_property("zhvjia_catalog_error", text or "")
    if not ctx.composition:empty() then ctx.composition:back().prompt = text or "" end
end

function M.project(env)
    local ctx = context(env)
    if not M.active(ctx) or type(ctx.set_preedit_projection) ~= "function" then return false end
    local raw, map = ctx.input, {}
    for i = 0, #raw do map[#map + 1] = i end
    local regions = {
        { start = 0, ["end"] = #ENTRY, style_key = "catalog.guide", highlightable = false },
    }
    if #raw > #ENTRY then
        regions[#regions + 1] = {
            start = #ENTRY, ["end"] = #raw,
            style_key = "catalog.suffix", highlightable = true,
        }
    end
    return ctx:set_preedit_projection({
        input_revision = ctx.input_revision, view_revision = ctx.view_revision,
        text = raw, raw_to_display = map,
        sel_start = #ENTRY, sel_end = math.max(#ENTRY, ctx.caret_pos or #raw),
        regions = regions,
    })
end

function S.func(segmentation, env)
    local ctx = context(env)
    if not M.active(ctx) then return true end
    local raw = ctx.input
    if segmentation.input ~= raw then segmentation.input = raw end
    while not segmentation:empty() do segmentation:pop_back() end
    local seg = Segment(0, #raw)
    seg.tags = seg.tags + Set({ TAG })
    segmentation:add_segment(seg)
    return false
end

function T.init()
    if snippets.Data then snippets.Data.reload() end
end

function T.func(_, seg, env)
    local ctx = context(env)
    if not M.active(ctx) or not seg:has_tag(TAG) then return end
    set_mode(ctx)
    local extension, filter, err = parse(ctx.input)
    if extension == nil then
        prompt(ctx, err)
        M.project(env)
        return
    end
    local rows, lookup_error = snippets.Data.catalog(extension, filter)
    if not rows or #rows == 0 then
        prompt(ctx, lookup_error or (filter ~= "" and ("没有匹配 " .. filter) or "没有片段"))
        M.project(env)
        return
    end
    prompt(ctx, "查片段")
    M.project(env) -- publish the view before the first suspended yield
    for _, item in ipairs(rows) do
        local body = snippets.Data.render(item, "space", nil, nil)
        if body and body ~= "" then
            local comment = (item.label or "") .. " [" .. item.code .. "]"
            local cand = Candidate(TYPE, 0, #ctx.input, body, comment)
            cand.quality = 1000000
            if type(Interaction) == "table" and type(Interaction.decorate) == "function" then
                cand = Interaction.decorate(cand, {
                    kind = "source", label = item.label or item.code,
                    style_key = "catalog.result",
                })
            end
            if type(ctx.make_atomic_candidate) == "function" then
                local atomic = ctx:make_atomic_candidate(cand)
                if atomic then yield(atomic) end
            else
                cand.preedit = ctx.input
                yield(cand)
            end
        end
    end
end

local function confirm(ctx, index)
    if ctx.composition:empty() then return end
    local seg = ctx.composition:back()
    local cand = index and seg:get_candidate_at(index) or ctx:get_selected_candidate()
    if not cand or cand.type ~= TYPE then return end
    if index ~= nil then ctx:select(index) else ctx:confirm_current_selection() end
end

local function digit_number(code)
    if code >= 0x31 and code <= 0x39 then return code - 0x30 end
    if code >= 0xFFB1 and code <= 0xFFB9 then return code - 0xFFB0 end
end

local function update(env, ctx)
    if not M.active(ctx) then
        if ctx:get_property("_interaction_mode") == "catalog" then clear_mode(ctx) end
        return
    end
    set_mode(ctx)
    if (ctx.caret_pos or #ctx.input) < #ENTRY and not env.catalog_adjusting then
        env.catalog_adjusting = true
        ctx.caret_pos = #ENTRY
        env.catalog_adjusting = false
    end
    M.project(env)
end

function P.init(env)
    local ctx = context(env)
    env.catalog_update = ctx.update_notifier:connect(function(c) update(env, c) end)
end

function P.fini(env)
    if env.catalog_update then env.catalog_update:disconnect(); env.catalog_update = nil end
    clear_mode(context(env))
end

function P.func(key, env)
    local ctx = context(env)
    if key:release() then return NOOP end
    if not M.active(ctx) then
        -- This exact reserved entry must be tried before ordinary code_mode.P.
        if not key:ctrl() and not key:alt() and not key:super() and not key:shift() and
            key.keycode == 0x60 and ctx.input == "chapianduan`" then
            set_mode(ctx)
            ctx:push_input("`")
            return ACCEPT
        end
        return NOOP
    end
    local repr = key:repr() or ""
    if repr == "Escape" then ctx:clear(); clear_mode(ctx); return ACCEPT end
    if repr == "Tab" or repr == "Shift+Tab" or repr == "ISO_Left_Tab" then return ACCEPT end
    if repr == "space" or repr == "Return" or repr == "KP_Enter" then
        confirm(ctx); return ACCEPT
    end
    if repr == "Control+BackSpace" or repr == "Shift+BackSpace" then
        local floor, pos = #ENTRY, ctx.caret_pos or #ctx.input
        local start = floor
        for i = floor + 1, pos do if ctx.input:sub(i, i) == "`" then start = i end end
        if pos > start then ctx:pop_input(pos - start) end
        return ACCEPT
    end
    if key:ctrl() or key:alt() or key:super() then return NOOP end
    local number = digit_number(key.keycode)
    if number then
        if not key:shift() and not ctx.composition:empty() then
            local config = env.engine.schema and env.engine.schema.config
            local size = (config and config:get_int("menu/page_size")) or 9
            size = size > 0 and size or 9
            local seg = ctx.composition:back()
            local index = math.floor((seg.selected_index or 0) / size) * size + number - 1
            if number <= size then confirm(ctx, index) end
        end
        return ACCEPT
    end
    local aliases = {
        KP_Left = "Left", KP_Right = "Right", KP_Home = "Home", KP_End = "End",
        KP_Delete = "Delete",
    }
    repr = aliases[repr] or repr
    local floor, last, pos = #ENTRY, #ctx.input, ctx.caret_pos or #ctx.input
    if repr == "Home" or repr == "End" or repr == "Left" or repr == "Right" then
        ctx:set_property("zhvjia_last_cursor_key",repr)
    end
    if repr == "Home" then ctx.caret_pos = floor; return ACCEPT end
    if repr == "End" then ctx.caret_pos = last; return ACCEPT end
    if repr == "Left" then ctx.caret_pos = pos > floor and pos - 1 or last; return ACCEPT end
    if repr == "Right" then ctx.caret_pos = pos < last and pos + 1 or floor; return ACCEPT end
    if repr == "BackSpace" then
        if pos > floor then ctx:pop_input(1) end
        return ACCEPT
    end
    if repr == "Delete" then
        if pos < last then ctx:delete_input(1) end
        return ACCEPT
    end
    if repr == "Up" or repr == "Down" or repr == "KP_Up" or repr == "KP_Down" or
        repr == "Page_Up" or repr == "Page_Down" or repr == "KP_Page_Up" or repr == "KP_Page_Down" then
        return NOOP
    end
    if key.keycode >= 32 and key.keycode < 127 then
        local char = string.char(key.keycode)
        if char:match("^[A-Za-z_`]$") then
            local proposed = ctx.input:sub(floor + 1, pos) .. char .. ctx.input:sub(pos + 1)
            -- Exactly one filter separator; incomplete fields remain editable.
            if proposed:match("^[A-Za-z_]*`?[A-Za-z_]*$") then ctx:push_input(char) end
        end
    end
    return ACCEPT
end

M.P, M.S, M.T = P, S, T
M.parse = parse
M.entry = ENTRY
return M
