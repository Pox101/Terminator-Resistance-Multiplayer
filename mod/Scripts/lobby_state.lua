local M={}
local allowed={idle=true,creating=true,lobby_ready=true,steam_unavailable=true,
    unsupported_api=true,overlay_unavailable=true,create_failed=true}
function M.decode(text)
    if type(text)~='string' or #text>160 then return nil end
    local state,err,members,id,transport=text:match('^TRMP_LOBBY1|([a-z_]+)|(%d+)|(%d+)|(%d+)|([01])%s*$')
    if not allowed[state] or #id>20 then return nil end
    err,members=tonumber(err),tonumber(members)
    if err>65535 or members>2 then return nil end
    return {state=state,error=err,members=members,lobby=id,transport=transport=='1'}
end
function M.message(s)
    if not s or s.state=='idle' then return 'Create a private Steam lobby and invite a friend.' end
    if s.state=='creating' then return 'Creating private Steam lobby...' end
    if s.state=='lobby_ready' then return string.format('Private Steam lobby: %d / 2 players',s.members) end
    if s.state=='overlay_unavailable' then return 'Enable Steam Overlay for this game, then restart the mod.' end
    if s.state=='steam_unavailable' then return 'Steam must be running and signed in.' end
    return 'Steam lobby could not be created. Please try again.'
end
return M
