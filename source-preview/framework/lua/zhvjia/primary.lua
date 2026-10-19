-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- Shared primary/creation editor. The raw caret is always the insertion point.
local config = require("zhvjia/config")
local runtime = require("zhvjia/runtime")
local auxiliary = require("zhvjia/auxiliary")
local points = require("zhvjia/breakpoints")
local M = {}
local ACCEPT, NOOP = 1,2
local ALIAS = { KP_Left="Left", KP_Right="Right", KP_Home="Home", KP_End="End", KP_Delete="Delete" }
local TONES = {
    ["ā"]="a",["á"]="a",["ǎ"]="a",["à"]="a",["ē"]="e",["é"]="e",["ě"]="e",["è"]="e",
    ["ī"]="i",["í"]="i",["ǐ"]="i",["ì"]="i",["ō"]="o",["ó"]="o",["ǒ"]="o",["ò"]="o",
    ["ū"]="u",["ú"]="u",["ǔ"]="u",["ù"]="u",["ǖ"]="v",["ǘ"]="v",["ǚ"]="v",["ǜ"]="v",["ü"]="v",
}
local function characters(s)
    local out = {}
    for at,cp in utf8.codes(s) do out[#out+1] = { at=at-1, finish=at-1+#utf8.char(cp), text=utf8.char(cp) } end
    return out
end
local function all_segments(ctx) return ctx.composition:toSegmentation():get_segments() end
local function fields(env) return auxiliary.fields(env.engine.context, config.get(env)) end
local function select_status(seg) return seg.status == "kSelected" or seg.status == "kConfirmed" end
local function map_piece(raw, display, candidate, selected)
    local map, chars = { [0]=0 }, characters(display)
    if selected and candidate and candidate.spans then
        local ok, spans = pcall(function() return candidate:spans().vertices end)
        if ok and spans and #spans == #chars+1 then
            for i,ch in ipairs(chars) do
                for offset = spans[i]-candidate.start+1,spans[i+1]-candidate.start do map[offset] = ch.finish end
            end
        end
    end
    if not map[#raw] then
        local cursor = 1
        for i=1,#raw do
            local wanted = raw:sub(i,i):lower()
            local found
            for j=cursor,#chars do
                local folded = TONES[chars[j].text] or chars[j].text:lower()
                if folded == wanted then found=j; break end
            end
            if found then map[i],cursor = chars[found].finish,found+1
            else map[i] = map[i-1] or 0 end
        end
    end
    local last = 0
    for i=0,#raw do last = math.max(last,map[i] or last); map[i]=last end
    map[#raw] = #display
    return map
end
-- Build a committable body, without prompt, labels or display-only Tips.
-- Selected native Phrase segments retain their text and original span data.
function M.view(env)
    local ctx, f = env.engine.context, fields(env)
    if not f then return nil end
    local raw, text, mapping, covered = ctx.input, "", { [0]=0 }, 0
    local active_start = f.floor
    local function append(start, ending, shown, candidate, selected)
        local offset = #text
        local local_map = map_piece(raw:sub(start+1,ending),shown,candidate,selected)
        for i=start,ending do mapping[i]=offset+(local_map[i-start] or 0) end
        text,covered = text..shown,ending
    end
    if f.floor > 0 then append(0,f.floor,"") end
    for _, seg in ipairs(all_segments(ctx)) do
        if seg.start >= f.floor and seg._end > seg.start and seg.start < f.main_end then
            if seg.start > covered then append(covered,seg.start,raw:sub(covered+1,seg.start)) end
            local cand = seg:get_selected_candidate()
            local ending = math.min(cand and cand._end or seg._end,f.main_end)
            if ending > covered and seg.start == covered then
                local selected = select_status(seg)
                local shown = selected and cand and cand.text or cand and cand.preedit
                if not shown or shown == "" then shown = raw:sub(seg.start+1,ending) end
                shown = shown:match("^[^\t`]*") or ""
                if not selected then active_start = seg.start end
                append(seg.start,ending,shown,cand and cand:get_genuine(),selected)
            end
        end
    end
    if covered < #raw then append(covered,#raw,raw:sub(covered+1)) end
    local last = 0
    local dense = {}
    for i=0,#raw do last=math.max(last,mapping[i] or last); dense[i+1]=last end
    dense[#raw+1]=#text
    local caret = ctx.caret_pos
    local right = caret == 0 and f.main_end or math.min(caret,f.main_end)
    local left = math.min(active_start,right)
    return { text=text, raw_to_display=dense, sel_start=dense[left+1], sel_end=dense[right+1], fields=f }
end
function M.enter_body(body)
    if not body then return body end
    -- Use the actual displayed text: tone_display can be enabled even when a
    -- candidate has no pronunciation annotation and still shows raw coding.
    for _,code in utf8.codes(body) do
        if TONES[utf8.char(code)] then return body end
    end
    return (body:gsub(" ",""))
end
function M.project(env)
    local ctx = env.engine.context
    if type(ctx.set_preedit_projection) ~= "function" then return false end
    local view = M.view(env)
    if not view then return false end
    local regions, f = {}, view.fields
    local main_start, main_end = view.raw_to_display[f.floor+1], view.raw_to_display[f.main_end+1]
    if main_end > main_start then regions[#regions+1]={start=main_start,["end"]=main_end,style_key="primary.body",highlightable=true} end
    if f.tick then
        local start = view.raw_to_display[f.tick]
        if #view.text > start then regions[#regions+1]={start=start,["end"]=#view.text,style_key="primary.auxiliary",highlightable=false} end
    end
    return ctx:set_preedit_projection({input_revision=ctx.input_revision,view_revision=ctx.view_revision,
        text=view.text,raw_to_display=view.raw_to_display,sel_start=view.sel_start,sel_end=view.sel_end,regions=regions})
end
function M.init(env)
    env.primary_select = env.engine.context.select_notifier:connect(function(ctx)
        local mode = runtime.of(env)
        if mode ~= "primary" then return end
        auxiliary.after_selection(ctx,env)
        if ctx:is_composing() then env._primary_undo={raw=ctx.input,caret=ctx.caret_pos,revision=ctx.input_revision} end
        M.project(env)
    end)
    env.primary_update = env.engine.context.update_notifier:connect(function(ctx)
        local undo = env._primary_undo
        if undo and (ctx.input~=undo.raw or ctx.caret_pos~=undo.caret or
            (undo.revision and ctx.input_revision~=undo.revision)) then env._primary_undo=nil end
        local mode = runtime.of(env)
        if mode == "primary" or mode == "creation" then M.project(env) end
    end)
end
function M.fini(env)
    if env.primary_select then env.primary_select:disconnect() end
    if env.primary_update then env.primary_update:disconnect() end
end
local function positions(env, f, floor)
    floor=floor or f.floor
    local raw, unit = env.engine.context.input, config.get(env).modes.primary.navigation
    local cache = env._breakpoints
    if not cache or cache.raw~=raw or cache.floor~=floor or cache.unit~=unit then
        cache={raw=raw,floor=floor,unit=unit,stops=points.for_input(raw,floor,unit)}; env._breakpoints=cache
    end
    return cache.stops
end
-- Moving the native caret before this boundary makes Compose discard selected
-- segments. Keep navigation in the unselected suffix; deletion owns reopening.
local function navigation_floor(env,f)
    local finish=f.floor
    for _,seg in ipairs(all_segments(env.engine.context)) do
        if seg._end>finish then
            if seg.start~=finish or not select_status(seg) then break end
            finish=seg._end
        end
    end
    return finish
end
function M.handle(key,env)
    local ctx, f = env.engine.context, fields(env)
    if not f or key:release() then return NOOP end
    local repr = ALIAS[key:repr()] or key:repr()
    local caret,raw = math.max(f.floor,ctx.caret_pos),ctx.input
    if key:alt() or key:super() then return NOOP end
    if repr=="Escape" then
        if f.tick then
            ctx.caret_pos=#raw; ctx:pop_input(#raw-f.main_end); ctx.caret_pos=math.min(caret,f.main_end)
        else ctx:clear() end
        env._primary_undo=nil; M.project(env); return ACCEPT
    end
    if repr=="BackSpace" and env._primary_undo then
        env._primary_undo=nil
        if ctx:reopen_previous_selection() then M.project(env); return ACCEPT end
    end
    local move = repr=="Left" or repr=="Right" or repr=="Home" or repr=="End" or repr=="Tab"
    local erase = repr=="BackSpace" or repr=="Delete" or repr=="Control+BackSpace" or repr=="Shift+BackSpace"
    if move or erase then
        env._primary_undo=nil
        ctx:confirm_previous_selection() -- marks earlier confirmation as edited
        if move then
            local floor=navigation_floor(env,f)
            caret=math.max(floor,caret)
            local stops=positions(env,f,floor)
            local target
            if repr=="Left" then target=points.previous(stops,caret) or #raw
            elseif repr=="Tab" then target=points.next(stops,caret) or floor
            elseif repr=="Right" then target=caret<#raw and caret+1 or floor
            elseif repr=="Home" then target=floor else target=#raw end
            ctx:set_property("zhvjia_last_cursor_key",repr)
            ctx.caret_pos=target
        elseif repr=="Delete" then if caret<#raw then ctx:delete_input(1) end
        elseif caret>f.floor then
            local stops=positions(env,f)
            local target=(repr=="BackSpace") and caret-1 or (points.previous(stops,caret) or f.floor)
            ctx:pop_input(caret-target)
        end
        M.project(env); return ACCEPT
    end
    if key:ctrl() then return NOOP end
    if key.keycode==0x60 and not key:shift() then
        if not f.tick and f.main_end>f.floor then
            ctx.caret_pos=#raw; ctx:push_input("`")
            if caret<#raw then ctx.caret_pos=caret end
        end
        env._primary_undo=nil; M.project(env); return ACCEPT
    end
    if key.keycode>=0x61 and key.keycode<=0x7a and not key:shift() then
        ctx:confirm_previous_selection(); env._primary_undo=nil
        ctx:push_input(string.char(key.keycode)); M.project(env); return ACCEPT
    end
    if key.keycode==0x27 and not key:shift() and f.mode~="creation" then
        if not f.tick or caret<f.tick then ctx:confirm_previous_selection(); ctx:push_input("'") end
        env._primary_undo=nil; M.project(env); return ACCEPT
    end
    return NOOP
end
-- Original cores lack arbitrary preedit projection. Keep the auxiliary text
-- visible using their standard Phrase preedit; exact blue/caret mapping is a
-- documented frontend downgrade, never a hidden extra Enter payload.
M.legacy={}
function M.legacy.tags_match(_,env)
    return type(env.engine.context.set_preedit_projection)~="function" and
        (fields(env) or {}).tick~=nil
end
function M.legacy.func(input,env)
    local ctx,f=env.engine.context,fields(env)
    for candidate in input:iter() do
        if f and f.tick and candidate._end==#ctx.input then
            local genuine=candidate:get_genuine()
            local preedit=genuine.preedit or ctx.input:sub(candidate.start+1,f.main_end)
            genuine.preedit=(preedit:match("^[^\t`]*") or preedit)..ctx.input:sub(f.tick)
        end
        yield(candidate)
    end
end
return M
