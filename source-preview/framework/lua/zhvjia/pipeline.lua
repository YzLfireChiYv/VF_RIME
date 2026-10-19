-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- Mode gates for retained Wanxiang filters. Each stage has its own original
-- environment, so migration does not mix caches, settings or notifier handles.
-- Native simplifiers retain their configured namespace and are gated here too.
local runtime = require("zhvjia/runtime")
local content = require("zhvjia/content")
local M = {}
local SPECS = {
    english = {
        module = "super_english", namespace = "*super_english",
        modes = { primary = true, unicode = true },
    },
    charset = {
        module = "super_filter", namespace = "*super_filter",
        modes = { primary = true, unicode = true, reverse = true },
    },
    comment = {
        module = "super_comment_preedit", namespace = "*super_comment_preedit",
        modes = { primary = true, unicode = true, reverse = true, creation = true },
    },
    hot = {
        module = "zhvjia/hot", member = "F", namespace = "*zhvjia.hot*F",
        modes = { primary = true, slash = true, reverse = true },
    },
    source = {
        module = "zhvjia/source_uniquify", member = "F",
        namespace = "*zhvjia.source_uniquify*F", modes = { primary = true, unicode = true },
    },
    emoji = {
        module = "zhvjia/emoji_group", member = "F",
        namespace = "*zhvjia.emoji_group*F", modes = { primary = true },
    },
    s2t = {
        native = "simplifier", namespace = "s2t",
        modes = { primary = true, unicode = true, reverse = true },
    },
    s2hk = {
        native = "simplifier", namespace = "s2hk",
        modes = { primary = true, unicode = true, reverse = true },
    },
    s2tw = {
        native = "simplifier", namespace = "s2tw",
        modes = { primary = true, unicode = true, reverse = true },
    },
    opencc = {
        native = "simplifier", namespace = "emoji_suggestion",
        modes = { primary = true },
    },
}

local function passthrough(input)
    for candidate in input:iter() do yield(candidate) end
end
local function content_allowed(name, env)
    if name == "opencc" then return content.includes(env, "emoji") end
    if name == "emoji" then
        return content.includes(env, "emoji") or content.includes(env, "functional_translation")
    end
    return true
end

local function load_stage(env, spec)
    if env._pipeline_stage then return env._pipeline_stage end
    if spec.native then
        assert(type(Component) == "table" and type(Component.Filter) == "function",
            "native filter component binding is unavailable: " .. spec.namespace)
        local native = Component.Filter(env.engine, spec.namespace, spec.native)
        assert(native, "cannot create native filter: " .. spec.namespace)
        local tags = {}
        local list = env.engine.schema.config:get_list(spec.namespace .. "/tags")
        if list then
            for i = 0, list.size - 1 do
                local value = list:get_value_at(i)
                if value then tags[#tags + 1] = value:get_string() end
            end
        end
        local state = { native = native, native_tags = tags }
        env._pipeline_stage = state
        return state
    end
    local module = require(spec.module)
    if spec.member then module = module[spec.member] end
    if type(module) == "function" then module = { func = module } end
    assert(type(module) == "table" and type(module.func) == "function",
        "invalid retained filter: " .. spec.module)
    local child = setmetatable({
        engine = env.engine, name_space = spec.namespace,
    }, { __index = env })
    local state = { module = module, env = child }
    env._pipeline_stage = state
    if module.init then
        local ok, why = pcall(module.init, child)
        if not ok then
            if module.fini then pcall(module.fini, child) end
            env._pipeline_stage = nil
            error(why, 0)
        end
    end
    return state
end

-- LuaFilter uses tags_match instead of its native TagMatching when present.
-- Preserve both an old Lua hook and an old native namespace/tags list.
local function original_tags_match(seg, state, spec)
    if state.native then
        -- Auxiliary has its own tag to keep creation and unrelated translators
        -- isolated. Simplifier::AppliesToSegment is exactly TagMatching:
        -- an empty scalar tag list matches all; otherwise any matching tag.
        -- Evaluate that read-only rule with a virtual abc tag. A constructed
        -- Segment value cannot be passed to its Segment* binding on old Lua.
        local tags = state.native_tags
        if #tags == 0 then return true end
        for _, tag in ipairs(tags) do
            if tag == "abc" or seg:has_tag(tag) then return true end
        end
        return false
    end
    local module, child = state.module, state.env
    if module.tags_match then return module.tags_match(seg, child) end
    local config = child.engine.schema.config
    local list = config:get_list(spec.namespace .. "/tags")
    if not list or list.size == 0 then return true end
    for i = 0, list.size - 1 do
        local value = list:get_value_at(i)
        if value and seg:has_tag(value.value) then return true end
    end
    return false
end

local TONELESS = {
    ["ā"] = "a", ["á"] = "a", ["ǎ"] = "a", ["à"] = "a",
    ["ē"] = "e", ["é"] = "e", ["ě"] = "e", ["è"] = "e",
    ["ī"] = "i", ["í"] = "i", ["ǐ"] = "i", ["ì"] = "i",
    ["ō"] = "o", ["ó"] = "o", ["ǒ"] = "o", ["ò"] = "o",
    ["ū"] = "u", ["ú"] = "u", ["ǔ"] = "u", ["ù"] = "u",
    ["ǖ"] = "ü", ["ǘ"] = "ü", ["ǚ"] = "ü", ["ǜ"] = "ü",
    ["ń"] = "n", ["ň"] = "n", ["ǹ"] = "n",
}
local function toneless(text)
    return (text:gsub("[%z\1-\127\194-\244][\128-\191]*", function(char)
        return TONELESS[char] or char
    end))
end

-- Creation's coding and preedit belong to its independent editor. Retain only
-- existing dictionary annotation; never mutate the genuine Phrase, rewrite
-- its preedit/body or update the legacy sequence/sticky properties here.
local function creation_comments(input, env)
    local ctx = env.engine.context
    local show = ctx:get_option("tone_hint") or ctx:get_option("toneless_hint") or
        ctx:get_option("fuzhu_hint") or ctx:get_option("chaifen_switch")
    local without_tones = ctx:get_option("toneless_hint") and
        not ctx:get_option("tone_hint") and not ctx:get_option("fuzhu_hint")
    for candidate in input:iter() do
        local comment = show and (candidate.comment or "") or ""
        if without_tones then comment = toneless(comment) end
        if comment == (candidate.comment or "") then
            yield(candidate)
        else
            yield(candidate:to_shadow_candidate(candidate.type, candidate.text, comment))
        end
    end
end

local function make_stage(name, spec)
    local stage = {}
    function stage.init(env) load_stage(env, spec) end
    function stage.fini(env)
        local state = env._pipeline_stage
        env._pipeline_stage = nil
        if state and state.module and state.module.fini then state.module.fini(state.env) end
    end
    function stage.tags_match(seg, env)
        local mode = runtime.of(env)
        if not spec.modes[mode] then return false end
        if not content_allowed(name, env) then return false end
        -- The read-only creation branch does not inherit an unrelated legacy
        -- comment tag restriction; it owns the independent creation segment.
        if name == "comment" and mode == "creation" then return true end
        local state = env._pipeline_stage or load_stage(env, spec)
        return original_tags_match(seg, state, spec)
    end
    function stage.func(input, env, candidates)
        local mode = runtime.of(env)
        if not spec.modes[mode] then return passthrough(input) end
        if not content_allowed(name, env) then return passthrough(input) end
        if name == "comment" and mode == "creation" then
            return creation_comments(input, env)
        end
        local state = env._pipeline_stage or load_stage(env, spec)
        if state.native then
            -- LuaFilter::Apply supplies its CandidateList* as the third Lua
            -- argument. Forward that exact pointer; neither a Lua {} nor nil
            -- is convertible to CandidateList* by the generic binding.
            local filtered = state.native:apply(input, candidates)
            if not filtered then return passthrough(input) end
            for candidate in filtered:iter() do yield(candidate) end
            return
        end
        return state.module.func(input, state.env)
    end
    return stage
end

for name, spec in pairs(SPECS) do M[name] = make_stage(name, spec) end
return M
