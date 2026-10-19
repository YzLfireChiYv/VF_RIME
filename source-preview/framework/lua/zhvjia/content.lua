-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- One associated-content owner. Input editing and physical gestures belong to
-- control/interaction; this module only changes a remembered provider choice.
local presentation = require("zhvjia/presentation")
local runtime = require("zhvjia/runtime")
local M = {}
local MODES = { "common", "english_translation", "emoji", "functional_translation", "none" }
local KNOWN = { common=true, emoji=true, english_translation=true, functional_translation=true, none=true }
local CLOCK_GROUPS = { date=true, ["time.minute"]=true, ["time.second"]=true,
    ["rqsj.minute"]=true, ["rqsj.second"]=true, ["sjrq.minute"]=true, ["sjrq.second"]=true }
local PROP = "zhvjia_content_mode"

local function config(env) return env.engine.schema and env.engine.schema.config end
local function fail(path, text) error(path .. ": " .. text, 0) end
local function path(env, name) return presentation.setting_path(env, "content/" .. name) end
local function read_keys(c, at, defaults)
    if not at then return defaults end
    if not c:is_list(at) then fail(at, "expected exact key names in a list") end
    local result = {}
    for i = 0, c:get_list_size(at) - 1 do
        local text = c:get_string(at .. "/@" .. i)
        local ok, key = pcall(KeyEvent, text or "")
        if not ok or not key or key.keycode == 0 or key:release() or
            (key.keycode>=0xffe1 and key.keycode<=0xffee) or key.keycode==0xff30 then fail(at, "invalid press key " .. tostring(text)) end
        if key.modifier == 0 and key.keycode >= 0x61 and key.keycode <= 0x7a then
            fail(at, "bare lowercase letters belong to the primary input")
        end
        result[#result + 1] = key:repr()
    end
    return result
end
local function keys(env, name, defaults) return read_keys(config(env), path(env, name), defaults) end
local function defaults()
    local out = { bindings={F13="cycle"}, default="common", presets={}, order={}, cycle={"common", "english_translation"},
        sources={ ["时间"]="time.minute", ["日期"]="date" } }
    for index, id in ipairs(MODES) do
        out.presets[id] = {enabled=index<=2, cycle=index<=2, keys={}}
        if index<=2 then out.order[#out.order+1]=id end
    end
    return out
end
local function compile(env)
    local initial = presentation.string(env, "content/default", "common")
    if initial ~= "preserve" and not KNOWN[initial] then fail("content/default", "unknown associated preset") end
    local out = defaults()
    out.bindings, out.default = {}, initial
    local c = config(env)
    local at = path(env, "presets")
    if at then
        if not c:is_list(at) then fail(at, "expected an ordered preset list") end
        out.presets, out.order, out.cycle = {}, {}, {}
        for i=0, c:get_list_size(at)-1 do
            local item=at.."/@"..i
            if not c:is_map(item) then fail(item, "expected id, cycle and keys") end
            local id=c:get_string(item.."/id")
            if not KNOWN[id] then fail(item.."/id", "unknown associated preset") end
            if out.presets[id] then fail(item.."/id", "duplicate preset "..id) end
            local cycle=c:get_bool(item.."/cycle")
            if cycle==nil and c:get_item(item.."/cycle") then fail(item.."/cycle", "expected true or false") end
            local direct=read_keys(c, c:get_item(item.."/keys") and item.."/keys" or nil, {})
            local enabled=cycle==true or #direct>0
            out.presets[id]={enabled=enabled, cycle=cycle==true, keys=direct}
            if enabled then out.order[#out.order+1]=id end
            if cycle then out.cycle[#out.cycle+1]=id end
        end
    end
    local function bind(key, action)
        if out.bindings[key] then fail("content", "key has two actions: "..key) end
        out.bindings[key]=action
    end
    for _, id in ipairs(MODES) do
        if #keys(env, "bindings/"..id, {})>0 then
            fail("content/bindings/"..id, "move direct keys to content/presets[].keys")
        end
        local preset=out.presets[id]
        if preset then for _, key in ipairs(preset.keys) do bind(key,id) end end
    end
    for _, action in ipairs({"cycle", "return_previous"}) do
        for _, key in ipairs(keys(env, "bindings/" .. action, action == "cycle" and {"F13"} or {})) do
            if out.bindings[key] then fail("content/bindings", "key has two actions: " .. key) end
            if action~="cycle" or #out.cycle>0 then bind(key,action) end
        end
    end
    local first = presentation.string(env, "content/hold/first", "")
    if first ~= "" then
        local ok, event = pcall(KeyEvent, first)
        if not ok or not event or event.keycode == 0 or event:release() or
            (event.keycode>=0xffe1 and event.keycode<=0xffee) or event.keycode==0xff30 or
            (event.modifier == 0 and event.keycode >= 0x20 and event.keycode <= 0x7e) then
            fail("content/hold/first", "expected a non-text press key")
        end
        out.hold = { first=event:repr(), secondary={}, unused_release="cycle" }
        for index, action in ipairs(out.order) do
            for _, key in ipairs(keys(env, "hold/secondary/" .. action, {tostring(index)})) do
                if KeyEvent(key).modifier~=0 then fail("content/hold/secondary", "use an unmodified second key; modified direct bindings are separate") end
                if key == out.hold.first or out.hold.secondary[key] then fail("content/hold", "duplicate key " .. key) end
                out.hold.secondary[key] = action
            end
        end
        for _, action in ipairs(MODES) do
            if not (out.presets[action] and out.presets[action].enabled) and #keys(env, "hold/secondary/"..action, {})>0 then
                fail("content/hold/secondary/"..action, "preset must first be enabled in content/presets")
            end
        end
    end
    at = path(env, "functional/sources")
    if at then
        if not c:is_map(at) then fail(at, "expected a source text to clock-group map") end
        out.sources = {}
        for _, text in ipairs(c:get_map(at):keys()) do
            local group = c:get_string(at .. "/" .. text)
            if group == "time" then group = "time.minute" end
            if not CLOCK_GROUPS[group] then
                fail(at .. "/" .. text, "expected date, time.minute/second, rqsj.minute/second or sjrq.minute/second")
            end
            out.sources[text] = group
        end
    end
    return out
end
local function options(env)
    local profile = presentation.profile(env)
    if not env._content_options or env._content_profile ~= profile then
        local ok, value = pcall(compile, env)
        if ok then env._content_options, env._content_error = value, nil
        else
            env._content_error = tostring(value)
            -- Invalid custom choices enable no new actions; ordinary defaults
            -- remain usable while the configuration error is reported.
            env._content_options = defaults()
            env._content_options.bindings = {}
        end
        env._content_profile = profile
        env.engine.context:set_property("zhvjia_content_error", env._content_error or "")
    end
    return env._content_options, env._content_error
end
function M.bindings(env)
    local value, err = options(env)
    return value.bindings, err
end
function M.action(env, key)
    if key:release() then return nil end
    return M.bindings(env)[key:repr()]
end
function M.hold(env)
    local configured = options(env).hold
    if not configured then return nil end
    local caps = presentation.capabilities(env)
    if not caps.key_release or not caps.focus_cancel or caps.epoch == "" then return nil end
    return configured
end
function M.configured_hold(env) return options(env).hold end
function M.enabled(env, id)
    local preset=options(env).presets[id]
    return preset and preset.enabled or false
end
function M.mode(env)
    local ctx = env.engine.context
    local settings=options(env)
    local value = ctx:get_property(PROP)
    if (value=="emoji" or value=="functional_translation") and not M.enabled(env,value) and M.enabled(env,"common") then value="common" end
    if not M.enabled(env,value) then
        value = settings.default
        if value == "preserve" then value = ctx:get_option("chinese_english") and "english_translation" or "common" end
        if not M.enabled(env,value) then value=settings.order[1] or "none" end
    end
    if ctx:get_property(PROP)~=value then
        ctx:set_property(PROP, value)
    end
    return value
end
function M.active(env, mode)
    return runtime.of(env) == "primary" and M.mode(env) == mode
end
function M.includes(env, provider)
    if runtime.of(env)~="primary" then return false end
    local mode=M.mode(env)
    return mode==provider or (mode=="common" and (provider=="emoji" or provider=="functional_translation"))
end
function M.emoji(env)
    return M.includes(env, "emoji") and env.engine.context:get_option("emoji_suggestion")
end
function M.functional_group(env, source)
    return options(env).sources[source.text]
end

local function source_of(env, candidate)
    local record = presentation.record_for(env, candidate)
    return record and record.source or candidate
end
local function same_source(a, b)
    if presentation.same_genuine(a, b) then return true end
    -- Re-querying constructs new Phrase objects. Source merging has already
    -- made this text/span unique; compare its semantic source, never its old
    -- numeric menu position or the currently selected derived translation.
    return a and b and a.text == b.text and a.start == b.start and a._end == b._end and
        a:get_genuine().type == b:get_genuine().type
end
function M.handle(env, action)
    local ctx = env.engine.context
    if runtime.of(env) ~= "primary" or not ctx:has_menu() then return false end
    local current, target = M.mode(env), action
    if action == "cycle" then
        local cycle=options(env).cycle
        target=cycle[1]
        for i, mode in ipairs(cycle) do if mode == current then target = cycle[i % #cycle + 1]; break end end
    elseif action == "return_previous" then
        target=M.enabled(env,"common") and "common" or options(env).order[1]
    end
    if not M.enabled(env,target) then return false end
    if current == target then return true end
    local selected = ctx:get_selected_candidate()
    local source = selected and source_of(env, selected)
    -- Keep the actual spelling, caret and confirmed segments. Only outstanding
    -- candidates are re-created. No option toggle, selection or commit occurs.
    ctx:set_property(PROP, target)
    presentation.forget(env)
    ctx:refresh_non_confirmed_composition()
    if source and not ctx.composition:empty() then
        local segment = ctx.composition:back()
        for index = 0, 511 do
            local candidate = segment:get_candidate_at(index)
            if not candidate then break end
            if not presentation.is_associated(env, candidate) and same_source(source, candidate) then
                ctx:highlight(index)
                break
            end
        end
    end
    return true
end
return M
