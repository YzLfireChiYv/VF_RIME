-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- Shared configuration injection for processor, segmentor and translator.
local config = require("zhvjia/config")
local runtime = require("zhvjia/runtime")
local code = require("zhvjia/code_mode")
local calculator = require("zhvjia/calculator_mode")
local catalog = require("zhvjia/catalog_mode")
local auxiliary = require("zhvjia/auxiliary")
local clock = require("zhvjia/clock")
local letters = require("zhvjia/letters")
local M, S, T = {}, {}, {}
function M.options(env)
    local snapshot = config.get(env)
    env.calculator_options = snapshot.modes.calculator
    env.creation_options = {prefix=snapshot.modes.creation.entry}
    env.code_options = snapshot.modes.code
    return snapshot
end
function S.init(env) M.options(env) end
function S.func(segmentation,env)
    local mode = runtime.of(env)
    if mode == "code" then return code.S.func(segmentation,env) end
    if mode == "calculator" then return calculator.S.func(segmentation,env) end
    if mode == "catalog" then return catalog.S.func(segmentation,env) end
    if mode == "reverse" then
        local _,entry=runtime.of(env)
        local raw=segmentation.input
        if #raw<#entry then raw=env.engine.context.input; segmentation.input=raw end
        local start=segmentation:get_current_start_position()
        if start<#entry then
            local prefix=Segment(0,#entry); prefix.tags=Set({"phony"}); prefix.status="kGuess"
            segmentation:add_segment(prefix)
            if #raw==#entry then return false end
            segmentation:forward(); start=#entry
        end
        if start<#raw then
            local body=Segment(start,#raw); body.tags=Set({"wanxiang_reverse"}); body.prompt="〔反查：拆分|笔画〕"
            segmentation:add_segment(body)
        end
        return false
    end
    if mode == "letters" then
        segmentation.input=env.engine.context.input
        while not segmentation:empty() do segmentation:pop_back() end
        local segment=Segment(0,#segmentation.input); segment.tags=Set({"zhvjia_letters"})
        segmentation:add_segment(segment); return false
    end
    if mode == "creation" or mode == "primary" or mode == "unicode" then
        return auxiliary.S.func(segmentation,env)
    end
    if mode == "clock" then
        segmentation.input=env.engine.context.input
        while not segmentation:empty() do segmentation:pop_back() end
        local segment=Segment(0,#segmentation.input)
        segment.tags=Set({"zhvjia_clock"})
        segmentation:add_segment(segment)
        return false
    end
    return true
end
function T.init(env)
    M.options(env)
    auxiliary.T.init(env)
    if code.T.init then code.T.init(env) end
end
function T.fini(env) auxiliary.T.fini(env) end
function T.func(input,seg,env)
    local mode = runtime.of(env)
    if mode == "code" then return code.T.func(input,seg,env) end
    if mode == "calculator" then return calculator.T.func(input,seg,env) end
    if mode == "catalog" then return catalog.T.func(input,seg,env) end
    if mode == "letters" then return letters.T.func(input,seg,env) end
    if mode == "creation" or seg:has_tag("zhvjia_aux") then return auxiliary.T.func(input,seg,env) end
    if (mode=="primary" or mode=="unicode") and seg:has_tag("abc") then return auxiliary.primary(input,seg,env) end
    if mode == "clock" then return clock.yield(seg,env,env.engine.context.input) end
    -- Remaining slash symbols belong to punct_translator. Do not call the old
    -- session translator: it contains fixed /= and snippet routes that would
    -- re-enable an entry after the central configuration had moved it.
end
M.S,M.T = S,T
return M
