-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- Routing is independent of candidate labels and visual theme.
local config = require("zhvjia/config")
local commands = require("zhvjia/slash_cmd")
local M = {}
local sequence=0
function M.mode(ctx, options)
    local raw = ctx.input or ""
    if raw == "" then return "idle" end
    if ctx:get_option("ascii_mode") then return "ascii" end
    if ctx:get_property("zhvjia_unicode") == "1" then return "unicode" end
    if ctx:get_property("zhvjia_code_session") ~= "" then return "code" end
    local owner
    for _, entry in ipairs(options and options.entries or {}) do
        if raw:sub(1, #entry.entry) == entry.entry then owner=entry; break end
    end
    if commands.kind_of(raw) and (not owner or (options.modes.clock.priority or 50)>owner.priority) then return "clock" end
    if owner then return owner.mode,owner.entry end
    if raw:match("^chapianduan``") then return "catalog" end
    if raw:match("^/[A-Za-z][A-Za-z]?%-[A-Za-z]*$") then return "letters" end
    for _,name in ipairs({"zimu","xiaoxiezimu","daxiezimu","quanzimu"}) do
        if raw:sub(1,#name+1)==name.."`" and raw:sub(#name+2):match("^[A-Za-z][A-Za-z]?%-[A-Za-z]*$") then return "letters" end
    end
    if raw:sub(1, 1) == "/" then return "slash" end
    if raw:find("/", 1, true) then return "literal" end
    if raw:find("``", 1, true) then return "invalid" end
    if raw:match("^[A-Za-z'`]+$") then return "primary" end
    return "literal"
end
function M.of(env) return M.mode(env.engine.context, config.get(env)) end
function M.primary(env) local mode = M.of(env); return mode == "primary" or mode == "unicode" end
function M.publish(env)
    local mode = M.of(env)
    local ctx = env.engine.context
    if mode=="idle" then ctx:set_property("zhvjia_input_session","")
    elseif ctx:get_property("zhvjia_input_session")=="" then
        sequence=sequence+1; ctx:set_property("zhvjia_input_session",tostring(sequence))
    end
    if ctx:get_property("_interaction_mode") ~= mode then ctx:set_property("_interaction_mode", mode) end
    return mode
end
return M
