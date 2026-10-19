-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- Primary/creation auxiliary lookup. It changes candidate eligibility, never
-- the pinyin parser or its independent cursor breakpoints.
local settings = require("zhvjia/config")
local runtime = require("zhvjia/runtime")
local backend = require("super_lookup").Backend
local M, S, T, F = {}, {}, {}, {}
function M.fields(ctx, options)
    local raw = ctx.input or ""
    local mode, entry = runtime.mode(ctx, options)
    local floor = mode == "creation" and #entry or 0
    local tick = raw:find("`", floor+1, true)
    if tick and raw:sub(tick+1):find("`",1,true) then return nil end
    if mode ~= "primary" and mode ~= "creation" and mode ~= "unicode" then return nil end
    return { floor = floor, tick = tick, main_end = tick and tick-1 or #raw,
        auxiliary = tick and raw:sub(tick+1) or "", mode = mode }
end
local function options(env) return settings.get(env) end
function M.after_selection(ctx, env)
    if env._aux_cleaning then return true end
    local fields = M.fields(ctx, options(env))
    if not fields or not fields.tick or ctx.composition:empty() then return true end
    -- A full candidate has consumed the suffix in its declared coverage.
    -- A partial choice preserves confirmed segments and removes only controls.
    local all = ctx.composition:toSegmentation():get_segments()
    for _, seg in ipairs(all) do
        if (seg.status == "kSelected" or seg.status == "kConfirmed") and seg._end >= #ctx.input then
            -- Auto-commit=false retains a full selection (creation, or an
            -- explicit device preference). Remove controls without throwing
            -- away that real Phrase and its dictionary code.
            local candidate = seg:get_selected_candidate()
            if candidate and candidate._end == #ctx.input then candidate._end = fields.main_end end
            seg._end = fields.main_end
        end
    end
    env._aux_cleaning = true
    ctx.caret_pos = #ctx.input
    ctx:pop_input(#ctx.input - fields.main_end)
    env._aux_cleaning = false
    return true
end
function S.init(env) settings.get(env) end
function S.func(segmentation, env)
    local ctx = env.engine.context
    local fields = M.fields(ctx, options(env))
    if not fields or (not fields.tick and fields.mode ~= "creation") then return true end
    local raw, floor = ctx.input, fields.floor
    local caret = ctx.caret_pos
    local ending = (caret == 0 or caret <= floor or caret > fields.main_end) and fields.main_end or caret
    -- Hide controls from the dictionary query, not from the real editable raw.
    local coverage = (fields.tick and ending==fields.main_end) and #raw or ending
    segmentation.input = raw:sub(1, coverage)
    local start = segmentation:get_current_start_position()
    if fields.mode == "creation" and start < floor then
        local prefix = Segment(0,floor)
        prefix.tags = Set({ "phony", "zhvjia_creation_prefix" })
        prefix.status = "kGuess"
        segmentation:add_segment(prefix)
        if ending > floor then segmentation:forward() else return false end
        start = floor
    end
    if start >= ending then return false end
    local seg = Segment(start,coverage)
    seg.tags = Set({ fields.mode == "creation" and "add_user_dict" or "zhvjia_aux" })
    segmentation:add_segment(seg)
    return false
end
function T.init(env)
    settings.get(env)
    -- Each user dictionary has one automatic Memory owner. Merely returning
    -- false from Memorize still starts/commits transactions in OnCommit, so a
    -- second query-only owner would break native Backspace learning undo.
    env.aux_main = Component.Translator(env.engine,"translator","script_translator")
    env.aux_created = Component.Translator(env.engine,"user_dict_set","script_translator")
    assert(env.aux_main,"main dictionary translator is required")
    assert(env.aux_created and type(env.aux_created.set_memorize_callback)=="function",
        "created dictionary translator callback is required")
    -- Existing created terms may keep their usage weights. Update the actual
    -- elements only; ScriptTranslator::Memorize would also save their joined
    -- text as a new phrase, which belongs to explicit creation instead.
    env.aux_created:set_memorize_callback(function(_,entry) return entry:update(1) end)
end
local function created_translation(translation)
    if not translation then return nil end
    return Translation(function()
        for candidate in translation:iter() do
            local genuine=candidate:get_genuine()
            local phrase=genuine and genuine.to_phrase and genuine:to_phrase()
            -- user_dict_set also has the main system dictionary attached for
            -- decoding. Do not expose its duplicate system phrases as created
            -- terms: choosing one would silently add it to created_terms.
            -- Keep exact user phrases only. The configured reader disables
            -- completion; a custom reader must not turn an ambiguous system
            -- completion into a supposedly existing created term.
            if phrase and genuine.type=="user_phrase" then
                yield(candidate)
            end
        end
    end)
end
function M.primary(input,seg,env)
    local merged=Menu()
    local main=env.aux_main:query(input,seg)
    local created=created_translation(env.aux_created:query(input,seg))
    if main then merged:add_translation(main) end
    if created then merged:add_translation(created) end
    local index=0
    while true do
        local candidate=merged:get_candidate_at(index)
        if not candidate then break end
        yield(candidate); index=index+1
    end
end
function T.fini(env)
    for _,name in ipairs({"aux_main","aux_created"}) do
        local provider=env[name]
        if provider and provider.disconnect then provider:disconnect() end
        env[name]=nil
    end
end
function T.func(input, seg, env)
    local is_creation = seg:has_tag("add_user_dict")
    if not is_creation and not seg:has_tag("zhvjia_aux") then return end
    local fields=M.fields(env.engine.context,options(env))
    local ending=math.min(seg._end,fields and fields.main_end or seg._end)
    local query = Segment(seg.start,ending)
    -- The real segment stays isolated as add_user_dict/zhvjia_aux. Only this
    -- dictionary query sees abc, so no other main-input providers are admitted.
    query.tags = Set({ "abc" })
    input=env.engine.context.input:sub(seg.start+1,ending)
    return M.primary(input,query,env)
end
function F.init(env) settings.get(env); backend.init(env) end
function F.tags_match(seg, env)
    local fields = M.fields(env.engine.context, options(env))
    return fields and fields.tick ~= nil and (seg:has_tag("zhvjia_aux") or seg:has_tag("add_user_dict")) or false
end
function F.func(input, env)
    local ctx, fields = env.engine.context, M.fields(env.engine.context, options(env))
    if not fields or not fields.tick then for cand in input:iter() do yield(cand) end; return end
    local budget = env.engine.schema.config:get_int("zhvjia/modes/primary/auxiliary_scan_limit") or 512
    budget=math.max(36,math.min(4096,budget))
    local prioritize=ctx:get_option("char_priority")
    local singles,phrases={},{}
    local scanned = 0
    for cand in input:iter() do
        scanned = scanned + 1
        if backend.matches(cand, fields.auxiliary, env) then
            if cand._end == fields.main_end then
                local wrapped = ShadowCandidate(cand,cand.type,cand.text,cand.comment or "")
                wrapped._end = #ctx.input
                cand=wrapped
            end
            if prioritize then
                local target=utf8.len(cand.text)==1 and singles or phrases
                target[#target+1]=cand
            else yield(cand) end
        end
        -- A malformed or unmatched auxiliary query must not drain the entire
        -- sentence translation in Lua. A new edit starts a new bounded query.
        if scanned >= budget then break end
    end
    if prioritize then
        for _,candidate in ipairs(singles) do yield(candidate) end
        for _,candidate in ipairs(phrases) do yield(candidate) end
    end
end
function F.fini(env)
    env.db_table,env.main_projection,env.xlit_projection=nil,nil,nil
    env._global_db_cache,env._global_comment_cache=nil,nil
end
M.S, M.T, M.F = S,T,F
return M
