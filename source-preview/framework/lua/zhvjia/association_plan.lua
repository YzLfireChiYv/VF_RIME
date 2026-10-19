-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- Compile a finite output-placement template once from Rime's merged config.
-- Pool indexes are 1-based after the provider has consumed a promoted Tip.
-- This module never queries a dictionary or treats an associated item as source.
local M = {}
local PATH = "zhvjia_associations/templates/emoji"
local MAX_SLOTS = 256

local function fail(path, reason) error(path .. ": " .. reason, 0) end
local function node(config, path) return config and config:get_item(path) end
local function map(config, path, allowed)
    local value = node(config, path)
    if not value then return false end
    if value.type ~= "kMap" then fail(path, "expected a map") end
    for _, key in ipairs(config:get_map(path):keys()) do
        if not allowed[key] then fail(path .. "/" .. key, "unknown field") end
    end
    return true
end
local function text(config, path)
    local value = node(config, path)
    if not value then return nil end
    if value.type ~= "kScalar" then fail(path, "expected a string") end
    local result = config:get_string(path)
    if type(result) ~= "string" then fail(path, "expected a string") end
    return result
end
local function style(config, path)
    local value = text(config, path)
    if value and (#value > 64 or not value:match("^[A-Za-z0-9_.-]*$")) then
        fail(path, "style_key allows at most 64 ASCII letters, digits, _, . and -")
    end
    return value
end
local function hint(config, path)
    local value = text(config, path)
    if value and (#value > 512 or value:find("[%z\r\n\t]")) then
        fail(path, "hint must be a single line of at most 512 bytes")
    end
    return value
end
local function compile(config, path)
    if not node(config, path) then return nil end
    map(config, path, { source = true, associated = true, remaining = true })
    local used, count = {}, 0
    local function index(at)
        local value = text(config, at)
        local output = value and tonumber(value)
        if not output or output % 1 ~= 0 or output < 1 or output > 9007199254740991 then
            fail(at, "expected a positive 1-based integer output index")
        end
        if used[output] then fail(at, "output index was already assigned at " .. used[output]) end
        used[output], count = at, count + 1
        if count > MAX_SLOTS then fail(path, "at most 256 explicit output slots are supported") end
        return output
    end
    local function rows(at)
        local value = node(config, at)
        if not value then return {} end
        if value.type ~= "kList" then fail(at, "expected an output-index list") end
        local result = {}
        for i = 0, config:get_list_size(at) - 1 do
            local item_path = at .. "/@" .. i
            local item = node(config, item_path)
            if not item then fail(item_path, "empty output slot") end
            if item.type == "kScalar" then
                result[#result + 1] = { output = index(item_path) }
            else
                map(config, item_path, { output = true, style_key = true, hint = true })
                result[#result + 1] = {
                    output = index(item_path .. "/output"),
                    style_key = style(config, item_path .. "/style_key"),
                    hint = hint(config, item_path .. "/hint"),
                }
            end
        end
        return result
    end
    local plan = { source = {}, associated = {} }
    local source_path = path .. "/source"
    if map(config, source_path, { rod = true, style_key = true }) then
        plan.source.style_key = style(config, source_path .. "/style_key")
        plan.source.rod = rows(source_path .. "/rod")
    else plan.source.rod = {} end
    local associated_path = path .. "/associated"
    if node(config, associated_path) then
        if node(config, associated_path).type ~= "kList" then fail(associated_path, "expected an association list") end
        for i = 0, config:get_list_size(associated_path) - 1 do
            local item_path = associated_path .. "/@" .. i
            map(config, item_path, { output = true, rod = true, style_key = true })
            plan.associated[#plan.associated + 1] = {
                output = index(item_path .. "/output"),
                style_key = style(config, item_path .. "/style_key"), rod = rows(item_path .. "/rod"),
            }
        end
    end
    plan.remaining = text(config, path .. "/remaining") or "associated"
    if plan.remaining ~= "associated" and plan.remaining ~= "last_rod" and plan.remaining ~= "source_rod" then
        fail(path .. "/remaining", "expected associated, last_rod or source_rod")
    end
    return plan
end

-- Absent and invalid plans both return nil; only an invalid plan has a diagnostic.
-- Callers keep their complete original default template in either case.
function M.load(config, path)
    local ok, value = pcall(compile, config, path or PATH)
    if ok then return value, nil end
    return nil, tostring(value)
end

local function output(value)
    if type(value) == "string" then return { text = value, type = "zhvg" } end
    return { candidate = value }
end
local function copy(value)
    local result = {}
    for key, item in pairs(value or {}) do result[key] = item end
    return result
end
function M.instantiate(plan, pool, source_spec, style_prefix)
    if not plan then return nil end
    style_prefix = style_prefix or "emoji"
    local source, associated, used = copy(source_spec), {}, {}
    source.rod = {}
    if plan.source.style_key ~= nil then source.style_key = plan.source.style_key end
    local function take(index)
        local value = pool[index]
        if value == nil or used[index] then return nil end
        used[index] = true
        return output(value)
    end
    local function rows(target, slots)
        for _, slot in ipairs(slots) do
            local row = take(slot.output)
            if row then
                row.kind, row.style_key, row.hint = "output", slot.style_key or (style_prefix .. ".rod"), slot.hint
                target[#target + 1] = row
            end
        end
    end
    rows(source.rod, plan.source.rod)
    for _, slot in ipairs(plan.associated) do
        local item = take(slot.output)
        if item then
            item.style_key, item.compact, item.rod = slot.style_key or (style_prefix .. ".associated"), true, {}
            rows(item.rod, slot.rod)
            associated[#associated + 1] = item
        end
        -- An absent association head owns no rod. Its in-range rod outputs
        -- remain unconsumed and are preserved by the remainder policy below.
    end
    for index = 1, #pool do
        if not used[index] then
            local item = take(index)
            if plan.remaining == "source_rod" then
                item.kind, item.style_key = "output", style_prefix .. ".rod"
                source.rod[#source.rod + 1] = item
            elseif plan.remaining == "last_rod" and #associated > 0 then
                item.kind, item.style_key = "output", style_prefix .. ".rod"
                local last = associated[#associated]
                last.rod[#last.rod + 1] = item
            else
                item.style_key, item.compact, item.rod = style_prefix .. ".associated", true, {}
                associated[#associated + 1] = item
            end
        end
    end
    return { source = source, associated = associated }
end
return M
