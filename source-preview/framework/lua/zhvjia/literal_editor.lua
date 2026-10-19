-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 YzLfireChiYv
-- Necessary editing whitelist shared by slash commands and pure reverse.
-- Unhandled events return NOOP; only the central router chooses a host exit.
local M={}
local ALIAS={KP_Left="Left",KP_Right="Right",KP_Home="Home",KP_End="End",KP_Delete="Delete"}
function M.handle(key,env,floor)
    local ctx=env.engine.context
    local raw,repr=ctx.input,ALIAS[key:repr()] or key:repr()
    floor=floor or 0
    if key:alt() or key:super() then return 2 end
    local caret=math.max(floor,ctx.caret_pos)
    if repr=="Tab" or repr=="Shift+Tab" or repr=="ISO_Left_Tab" then return 1 end
    if repr=="Left" or repr=="Right" or repr=="Home" or repr=="End" then
        local target
        if repr=="Left" then target=caret>floor and caret-1 or #raw
        elseif repr=="Right" then target=caret<#raw and caret+1 or floor
        elseif repr=="Home" then target=floor else target=#raw end
        ctx:set_property("zhvjia_last_cursor_key",repr); ctx.caret_pos=target
        return 1
    end
    if repr=="Control+BackSpace" or repr=="Shift+BackSpace" then
        if caret>floor then ctx:pop_input(caret-floor) end; return 1
    end
    if key:ctrl() then return 2 end
    if repr=="BackSpace" then if caret>floor then ctx:pop_input(1) end; return 1 end
    if repr=="Delete" then if caret<#raw then ctx:delete_input(1) end; return 1 end
    return 2
end
return M
