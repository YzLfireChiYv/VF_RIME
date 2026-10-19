-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- Independent, deliberately small word creation editor.
--
-- The router owns admission to /+ and the shared primary/auxiliary editor.
-- While this mode owns the input, only its ordinary dictionary translator and
-- auxiliary filter may run.  Selecting a candidate uses Context::Select with
-- _auto_commit=false, so keyboard, mouse and API all confirm inside composition.
-- Only finish() writes created_terms and outputs text; it never calls
-- Context::Commit and therefore does not trigger ordinary learning notifiers.
local M, P = {}, {}
local ACCEPT, NOOP = 1, 2
local DEFAULT_PREFIX = "/+"
local PROPERTY = "zhvjia_creation_error"
local SWITCH = { [0xFFE1] = true, [0xFFE2] = true, [0xFFE5] = true }
local NAVIGATION = {
    Left = true, Right = true, Home = true, End = true, Tab = true,
    ISO_Left_Tab = true, Up = true, Down = true, Page_Up = true,
    Page_Down = true, KP_Left = true, KP_Right = true, KP_Home = true,
    KP_End = true, KP_Up = true, KP_Down = true, KP_Page_Up = true,
    KP_Page_Down = true,
}

local function options(env)
    return env.creation_options or {}
end

local function prefix(env)
    return options(env).prefix or DEFAULT_PREFIX
end

function M.active(ctx, env)
    local entry = env and prefix(env) or DEFAULT_PREFIX
    return ctx and type(ctx.input) == "string" and
        ctx.input:sub(1, #entry) == entry
end

-- Validity is intentionally independent of the translator's permissive old
-- recognizer. Admission of a key must not silently enable another input mode.
function M.valid_body(body)
    return type(body) == "string" and
        (body:match("^[a-z]*$") ~= nil or body:match("^[a-z]+`[a-z]*$") ~= nil)
end

local function error_message(env, message)
    env.engine.context:set_property(PROPERTY, message or "")
    local ctx = env.engine.context
    if not ctx.composition:empty() then
        ctx.composition:back().prompt = message and ("〔" .. message .. "〕") or "〔造词〕"
    end
end

local function segments(ctx)
    return ctx.composition:toSegmentation():get_segments()
end

local function segment_at(ctx, index)
    return ctx.composition:toSegmentation():get_at(index)
end

local function selected(seg)
    return seg.status == "kSelected" or seg.status == "kConfirmed"
end

local function revision(ctx)
    -- The fork exposes an opaque revision token. Raw/caret guards below also
    -- work on original clients, whose Context has no revision property.
    return ctx.input_revision
end

local function release_memory(state)
    if not state then return end
    local memory=state.memory
    state.memory=nil
    -- Memory:disconnect clears its dictionary handles. It is appropriate for
    -- this short-lived explicit writer, not for an active query translator.
    if memory then pcall(function() memory:disconnect() end) end
end

local function sync(env)
    local ctx, state = env.engine.context, env._creation
    if not state then return end
    local active = M.active(ctx, env)
    if active and not state.active then
        state.active = true
        state.saved_auto_commit = ctx:get_option("_auto_commit")
        state.undo = nil
        ctx:set_option("_auto_commit", false)
        ctx:set_property("zhvjia_creation", "1")
    elseif not active and state.active then
        release_memory(state)
        state.active = false
        state.undo = nil
        ctx:set_option("_auto_commit", state.saved_auto_commit)
        ctx:set_property("zhvjia_creation", "")
        ctx:set_property(PROPERTY, "")
    end
    local undo = state.undo
    if undo and (ctx.input ~= undo.raw or ctx.caret_pos ~= undo.caret or
        (undo.revision ~= nil and revision(ctx) ~= undo.revision)) then
        state.undo = nil
    end
end

function M.init(env)
    if env._creation then return end
    local ctx = env.engine.context
    env._creation = { active = false, suppressed_switches = {} }
    env._creation.update = ctx.update_notifier:connect(function() sync(env) end)
    env._creation.selection = ctx.select_notifier:connect(function(c)
        if not M.active(c, env) then return end
        sync(env)
        -- The shared auxiliary editor removes its control suffix after the
        -- native selection, including selections coming directly from mouse
        -- or API. Do this before recording the undo revision/caret.
        if env.creation_after_selection then
            local ok, result = pcall(env.creation_after_selection, c, env)
            if not ok or result == false then
                env._creation.undo = nil
                error_message(env, "辅码选词未完成，输入已保留")
                return
            end
        end
        -- The engine's earlier selection listener closes/forwards the segment.
        -- Remember its index, including the fully converted kConfirmed case.
        local all = segments(c)
        for i = #all, 1, -1 do
            local seg = all[i]
            if seg._end > #prefix(env) and selected(seg) and
                seg:get_selected_candidate() then
                env._creation.undo = {
                    raw = c.input, caret = c.caret_pos, revision = revision(c),
                    index = i - 1, start = seg.start, finish = seg._end,
                }
                break
            end
        end
        error_message(env)
    end)
    sync(env)
end

function M.fini(env)
    local state = env._creation
    if not state then return end
    if state.update then state.update:disconnect() end
    if state.selection then state.selection:disconnect() end
    if state.active then
        env.engine.context:set_option("_auto_commit", state.saved_auto_commit)
        env.engine.context:set_property("zhvjia_creation", "")
    end
    release_memory(state)
    env._creation = nil
end

function M.enter(env)
    M.init(env)
    sync(env)
    return env._creation.active
end

function M.leave(env)
    -- Restore only after the router has removed this mode's input. Calling
    -- leave while /+ is still present must not re-enable auto commit.
    sync(env)
end

function M.edited(env)
    if env._creation then env._creation.undo = nil end
end

function M.undo_selection(env)
    local ctx, state = env.engine.context, env._creation
    sync(env)
    local undo = state and state.undo
    if not undo or ctx.input ~= undo.raw or ctx.caret_pos ~= undo.caret then
        return false
    end
    local seg = segment_at(ctx, undo.index)
    if not seg or not selected(seg) or seg.start ~= undo.start or
        seg._end ~= undo.finish then
        state.undo = nil
        return false
    end
    -- ReopenPreviousSelection ordinarily refuses kConfirmed (the native final
    -- selection). This mode did not commit it, so it is still safe to undo.
    seg.status = "kSelected"
    state.undo = nil
    return ctx:reopen_previous_selection()
end

local function get_memory(env)
    local state = env._creation
    if state.memory then return state.memory end
    local config = env.engine.schema.config
    if config:get_string("add_user_dict/user_dict") ~= "created_terms" or
        config:get_bool("add_user_dict/enable_user_dict") ~= true then
        return nil, "造词词库配置不可用"
    end
    local ok, memory = pcall(Memory, env.engine, env.engine.schema, "add_user_dict")
    if not ok or not memory then return nil, "无法打开造词词库" end
    state.memory = memory
    return memory
end

-- Return a real Phrase, never a reconstructed Phrase or a comment-derived code.
function M.ordinary(candidate)
    if not candidate or not candidate.get_genuine then return nil end
    local genuine = candidate:get_genuine()
    local phrase = genuine and genuine.to_phrase and genuine:to_phrase()
    if not phrase or phrase.text == "" or candidate.text ~= phrase.text then return nil end
    -- Source isolation is the router/translator tag gate, not a blacklist of
    -- output characters. Real entries such as “维生素B” retain their real code.
    -- In particular, no English provider may enter this mode's translation.
    return phrase
end

-- Inspect the actual converted segments, not HasFinishedComposition alone:
-- that function only examines the last nonempty segment and can miss a gap.
function M.collect(env, memory)
    local ctx, entry = env.engine.context, prefix(env)
    local raw = ctx.input or ""
    if not M.active(ctx, env) or not M.valid_body(raw:sub(#entry + 1)) then
        return nil, "造词仅允许小写字母和一个辅码引导符"
    end
    local end_pos, texts, codes = #entry, {}, {}
    for _, seg in ipairs(segments(ctx)) do
        if seg._end > #entry then
            if seg.start == seg._end then
                if seg.start ~= #raw then return nil, "还有未选定的拼音" end
            else
                if seg.start ~= end_pos or not selected(seg) then
                    return nil, "还有未选定的拼音"
                end
                local candidate = seg:get_selected_candidate()
                local phrase = M.ordinary(candidate)
                if not phrase or candidate.start ~= seg.start or
                    candidate._end ~= seg._end then
                    return nil, "选词缺少可保存的原始词条"
                end
                local decoded = memory:decode(phrase.code)
                if not decoded or #decoded == 0 then return nil, "无法读取选词的真实编码" end
                for _, code in ipairs(decoded) do
                    if type(code) ~= "string" or code == "" or code:find("[%s\t\r\n]") then
                        return nil, "选词的词典编码无效"
                    end
                    codes[#codes + 1] = code
                end
                texts[#texts + 1] = phrase.text
                end_pos = seg._end
            end
        end
    end
    if end_pos ~= #raw or #texts == 0 then return nil, "请先选完要保存的词" end
    return { text = table.concat(texts), custom_code = table.concat(codes, " ") .. " " }
end

function M.finish(env)
    M.init(env)
    sync(env)
    release_memory(env._creation)
    if not env._creation.active then return false end
    local memory, why = get_memory(env)
    if not memory then error_message(env, why); return false end
    local word
    -- A failed update/transaction must keep the composition and never pretend
    -- that a word was saved. Collect and allocation are inside the guard too:
    -- incomplete input or any binding error must release this temporary Memory.
    -- No commit notifier is emitted on this path.
    local began, stored, finished = false, false, false
    local ok = pcall(function()
        word, why = M.collect(env, memory)
        if not word then return end
        local entry = DictEntry()
        entry.text, entry.custom_code, entry.weight = word.text, word.custom_code, 1
        began = memory:start_session()
        if not began then return end
        stored = memory:update_userdict(entry, 1, "")
        if stored then finished = memory:finish_session() end
    end)
    if ok and not word then
        release_memory(env._creation)
        error_message(env, why)
        return false
    end
    if not ok or not began or not stored or not finished then
        if began and not finished then pcall(function() memory:discard_session() end) end
        release_memory(env._creation)
        error_message(env, "保存失败，输入已保留")
        return false
    end
    release_memory(env._creation)
    env.engine:commit_text(word.text)
    env.engine.context:clear()
    sync(env)
    return true
end

local function digit_index(key)
    local kc = key.keycode
    if kc >= 0x31 and kc <= 0x39 then return kc - 0x31 end
    if kc >= 0xFFB1 and kc <= 0xFFB9 then return kc - 0xFFB1 end
    return nil
end

local function choose(env, index)
    local ctx = env.engine.context
    if not ctx:has_menu() or ctx.composition:empty() then return false end
    local seg = ctx.composition:back()
    if index ~= nil then
        local page_size = env.engine.schema.page_size
        if not page_size or page_size < 1 then page_size = 9 end
        index = math.floor(seg.selected_index / page_size) * page_size + index
    else
        index = seg.selected_index
    end
    if not M.ordinary(seg:get_candidate_at(index)) then return false end
    return ctx:select(index)
end

-- edit(key, env) is the router's shared primary/auxiliary editor. Returning
-- NOOP lets the router choose an admitted candidate action or the common
-- host fallback, never the old special-mode processor chain.
function M.handle(key, env, edit)
    M.init(env)
    sync(env)
    local ctx, state = env.engine.context, env._creation
    local kc, repr = key.keycode, key:repr() or ""
    if key:release() and state.suppressed_switches[kc] then
        state.suppressed_switches[kc] = nil
        return ACCEPT
    end
    if not state.active then return NOOP end
    if SWITCH[kc] then
        if not key:release() then state.suppressed_switches[kc] = true end
        return ACCEPT
    end
    if key:release() then return NOOP end
    if key.caps and key:caps() then
        return env.engine:process_key(KeyEvent(kc, key.modifier - 2)) and ACCEPT or 0
    end
    if repr == "Control+Return" or repr == "Control+KP_Enter" then
        M.finish(env)
        return ACCEPT
    end
    if key:alt() or key:super() then return NOOP end
    if key:ctrl() then
        if repr == "Control+BackSpace" then
            M.edited(env)
            return edit and edit(key, env) or ACCEPT
        end
        return NOOP -- central control owns the host fallback for unknown combinations
    end
    if repr == "Escape" then
        if ctx.input:find("`", #prefix(env) + 1, true) and edit then
            M.edited(env)
            return edit(key, env)
        end
        ctx:clear()
        return ACCEPT
    end
    if repr == "BackSpace" and M.undo_selection(env) then return ACCEPT end
    if repr == "BackSpace" or repr == "Shift+BackSpace" or repr == "Delete" or
        repr == "KP_Delete" then
        M.edited(env)
        if edit then return edit(key, env) end
        -- Prefix is not editable body. No fallback into express_editor's
        -- Commit-or-raw path when an integration forgot the shared editor.
        if repr == "BackSpace" and ctx.caret_pos > #prefix(env) then ctx:pop_input(1) end
        if (repr == "Delete" or repr == "KP_Delete") and
            ctx.caret_pos >= #prefix(env) then ctx:delete_input(1) end
        return ACCEPT
    end
    if repr == "space" or repr == "Return" or repr == "KP_Enter" then
        choose(env)
        return ACCEPT
    end
    if not key:shift() then
        local index = digit_index(key)
        if index ~= nil then choose(env, index); return ACCEPT end
    end
    if NAVIGATION[repr] then
        M.edited(env)
        return edit and edit(key, env) or NOOP
    end
    local char = kc >= 0x61 and kc <= 0x7A and string.char(kc) or nil
    if char and not key:shift() then
        local caret = ctx.caret_pos
        if caret < #prefix(env) then ctx.caret_pos = #prefix(env) end
        M.edited(env)
        if edit then
            local result = edit(key, env)
            if result ~= NOOP then return result end
        end
        ctx:push_input(char)
        return ACCEPT
    end
    if kc == 0x60 and not key:shift() and edit then
        M.edited(env)
        return edit(key, env) -- shared helper enforces one trailing aux field
    end
    return ACCEPT
end

function P.init(env) M.init(env) end
function P.fini(env) M.fini(env) end
function P.func(key, env) return M.handle(key, env, env.creation_edit) end
M.P = P
return M
