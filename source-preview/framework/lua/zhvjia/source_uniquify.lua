-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- Ordinary source merge. Runs after s2t, before OpenCC emoji_suggestion.
-- Same text+span ordinary candidates become one UniquifiedCandidate (append,
-- first yield). Already structured / associated items keep identity.
-- Learning still uses genuines[1]. This stage does not build rods or drop faces.

local function is_special(cand)
    local t = cand and cand.type
    return type(t) == "string" and
        (t:sub(1, 12) == "zhvjia_clock" or t:sub(1, 14) == "zhvjia_snippet")
end

local function is_structured(cand)
    if is_special(cand) then
        return true
    end
    local kind = cand and cand.interaction_kind
    return type(kind) == "string" and kind ~= ""
end

local function source_key(cand)
    return table.concat({ cand.text or "", tostring(cand.start), tostring(cand._end) }, "\0")
end

local function as_uniquified(cand)
    if not cand or not cand.to_uniquified_candidate then
        return nil
    end
    local ok, wrapped = pcall(function()
        -- Keep the first item's semantic type string. Downstream filters
        -- (emoji excluded_types, etc.) match type(), not the Uniquified dynamic class.
        return cand:to_uniquified_candidate(cand.type)
    end)
    if ok and wrapped then
        return wrapped
    end
    return nil
end

local function try_append(core, cand)
    if not core or not cand or not core.append then
        return false
    end
    local ok, appended = pcall(function()
        return core:append(cand)
    end)
    return ok and appended == true
end

local F = {}

function F.func(input)
    local seen = {}
    for cand in input:iter() do
        if is_structured(cand) then
            yield(cand)
        else
            local key = source_key(cand)
            local prev = seen[key]
            if prev then
                if not try_append(prev, cand) then
                    yield(cand)
                end
            else
                local core = as_uniquified(cand)
                if core then
                    seen[key] = core
                    yield(core)
                else
                    seen[key] = cand
                    yield(cand)
                end
            end
        end
    end
end

return { F = F }
