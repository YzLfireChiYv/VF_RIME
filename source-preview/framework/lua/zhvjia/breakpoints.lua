-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- Candidate-independent cursor stops. No dictionary traversal or word scores.
local spelling = require("zhvjia/pinyin_shape")
local M = {}
local COMPOUND = { ai = true, ei = true, ao = true, ou = true }
local function word_stops(word)
    local n, edges = #word, {}
    if n > 2048 then local out = {}; for i = 0,n do out[i] = true end; return out end
    local function boundary(i)
        return i == 0 or i == n or not COMPOUND[word:sub(i,i+1)]
    end
    for i = 0,n-1 do
        edges[i] = {}
        for j = i+1, math.min(n,i+6) do
            if boundary(i) and boundary(j) and spelling.syllable(word:sub(i+1,j)) then
                edges[i][#edges[i]+1] = { j, 0 }
            end
        end
    end
    -- Full spelling has priority. Only if impossible admit initial letters,
    -- an incomplete final spelling, and finally independently editable errors.
    local function paths(fallback)
        local left, right = { [0] = 0 }, { [n] = 0 }
        local all = {}
        for i = 0,n-1 do
            all[i] = {}; for _, e in ipairs(edges[i]) do all[i][#all[i]+1] = e end
            if fallback then
                all[i][#all[i]+1] = { i+1, word:sub(i+1,i+1):match("[bpmfdtnlgkhjqxrzcsyw]") and 2 or 8 }
                if n-i <= 6 and spelling.prefix(word:sub(i+1)) then all[i][#all[i]+1] = { n, 1 } end
            end
            if left[i] then
                for _, e in ipairs(all[i]) do
                    local cost = left[i]+e[2]
                    if not left[e[1]] or cost < left[e[1]] then left[e[1]] = cost end
                end
            end
        end
        if not left[n] then return nil end
        for i = n-1,0,-1 do
            for _, e in ipairs(all[i]) do
                if right[e[1]] then
                    local cost = e[2]+right[e[1]]
                    if not right[i] or cost < right[i] then right[i] = cost end
                end
            end
        end
        local out = { [0] = true, [n] = true }
        for i = 0,n-1 do
            for _, e in ipairs(all[i]) do
                if left[i] and right[e[1]] and left[i]+e[2]+right[e[1]] == left[n] then
                    out[i], out[e[1]] = true, true
                end
            end
        end
        return out
    end
    return paths(false) or paths(true)
end
function M.for_input(raw, floor, unit)
    floor = floor or 0
    local stops, tick = { [floor] = true, [#raw] = true }, raw:find("`",floor+1,true)
    local main_end = tick and tick-1 or #raw
    if unit == "character" then
        for i = floor, #raw do stops[i] = true end
    else
        local at = floor+1
        while at <= main_end do
            local start, finish = raw:find("[a-zA-Z]+",at)
            if not start or start > main_end then
                for i = at-1,main_end do stops[i] = true end; break
            end
            finish = math.min(finish,main_end)
            for i = at-1,start-1 do stops[i] = true end
            for offset in pairs(word_stops(raw:sub(start,finish):lower())) do stops[start-1+offset] = true end
            at = finish+1
        end
        -- Auxiliary code is a literal field. Both sides of its guide, like
        -- both sides of an explicit apostrophe, are real editable stops.
        if tick then for i = tick-1,#raw do stops[i] = true end end
    end
    local out = {}; for value in pairs(stops) do out[#out+1] = value end
    table.sort(out); return out
end
function M.previous(stops, pos)
    for i = #stops,1,-1 do if stops[i] < pos then return stops[i] end end
end
function M.next(stops, pos)
    for _, stop in ipairs(stops) do if stop > pos then return stop end end
end
return M
