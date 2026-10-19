-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- A dictionary-free API example, deliberately independent of production modules.
local M = { P = {}, T = {} }
local ACCEPT, NOOP, REJECT = 1, 2, 0
local PRESET = "association_demo_preset"

local function native_available()
  return type(Interaction) == "table"
      and type(Interaction.decorate) == "function"
      and type(Interaction.attach) == "function"
      and type(Interaction.get_snapshot) == "function"
end

local function rods_enabled(env)
  return native_available() and env.engine.schema.config:get_string(
      "association_demo/presentation") == "rods"
end

local function payload(seg, text, comment)
  return Candidate("association_demo", seg.start, seg._end, text, comment or "")
end

local function first_rod(env)
  local context = env.engine.context
  if context.composition:empty() then return false end
  local snapshot = Interaction.get_snapshot(env.engine)
  if not snapshot then return false end
  if not snapshot:is_current() then snapshot:free(); return false end
  local items, parent, first = snapshot:items()
  local index = context.composition:back().selected_index
  for _, item in ipairs(items) do
    if item.menu_index == index then parent = item.id; break end
  end
  for _, item in ipairs(items) do
    if parent and item.attached_to_id == parent and item.action == "commit"
        and (not first or item.rod_index < first.rod_index) then
      first = item
    end
  end
  local selected = first and snapshot:select(first.id) == 1
  snapshot:free()
  return selected == true
end

function M.P.func(key, env)
  local context = env.engine.context
  -- Unhandled application shortcuts bypass speller/editor and do not commit.
  local modified = key:ctrl() or key:alt() or key:super()
  if key:release() then return modified and REJECT or NOOP end
  if context.input == "demo" and key:ctrl()
      and not key:alt() and not key:super() and not key:shift() then
    local preset
    if key.keycode == 0xffca then preset = "common" end -- F13
    if key.keycode == 0xffcc then preset = "english" end -- F15
    if preset then
      if context:get_property(PRESET) ~= preset then
        context:set_property(PRESET, preset)
        context:refresh_non_confirmed_composition()
      end
      return ACCEPT
    end
    if key.keycode == string.byte("1") and rods_enabled(env) then
      first_rod(env)
      return ACCEPT -- An absent rod does nothing; no unrelated row is selected.
    end
  end
  return modified and REJECT or NOOP
end

function M.T.func(input, seg, env)
  if input ~= "demo" then return end
  local source = payload(seg, "示例", "source")
  local english = env.engine.context:get_property(PRESET) == "english"
  -- These are small authored examples, not a dictionary or network translation.
  local associated = payload(seg, english and "example" or "😀",
      english and "English mapping" or "emoji")
  local instant = os.time()
  local source_rows = english and {} or {
    payload(seg, os.date("%H:%M:%S", instant), "local time"),
    payload(seg, os.date("%Y-%m-%d", instant), "local date"),
  }
  local associated_rows = english and {
    payload(seg, "sample"), payload(seg, "demonstration"),
  } or {
    payload(seg, "😮"), payload(seg, "😯"),
  }

  if rods_enabled(env) then
    source = Interaction.decorate(source, { kind = "source" })
    associated = Interaction.decorate(associated,
        { kind = "associated", source = source })
    local function attach(parent, rows)
      local outputs = {}
      for _, candidate in ipairs(rows) do
        outputs[#outputs + 1] = { kind = "output", candidate = candidate }
      end
      if #outputs > 0 then Interaction.attach(parent, outputs) end
    end
    attach(source, source_rows)
    attach(associated, associated_rows)
    yield(source)
    yield(associated)
  else
    yield(source)
    for _, candidate in ipairs(source_rows) do yield(candidate) end
    yield(associated)
    for _, candidate in ipairs(associated_rows) do yield(candidate) end
  end
end

return M
