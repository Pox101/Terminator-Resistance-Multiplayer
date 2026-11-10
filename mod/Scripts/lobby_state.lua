local M={}
local allowed={idle=true,creating=true,lobby_ready=true,steam_unavailable=true,
    unsupported_api=true,overlay_unavailable=true,create_failed=true,
    invitation_pending=true,joining=true,join_failed=true,incompatible=true,
    transport_connecting=true,transport_ready=true,transport_failed=true,
    peer_disconnected=true,owner_left=true,local_transport_test=true}
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
    if s.state=='invitation_pending' then return 'Invitation accepted. Return to the main menu to join.' end
    if s.state=='joining' then return 'Joining the invited Steam lobby...' end
    if s.state=='transport_connecting' then return 'Connecting through Steam relay...' end
    if s.state=='transport_ready' then return 'Steam party connected. Host: start New Infiltrator Mode.' end
    if s.state=='incompatible' then return 'Incompatible mod/game content, or an untrusted lobby.' end
    if s.state=='join_failed' then return 'Could not join the invited lobby. Ask for a new invitation.' end
    if s.state=='transport_failed' then return 'Steam relay connection failed. No direct-IP fallback is used.' end
    if s.state=='peer_disconnected' or s.state=='owner_left' then return 'The other player left or the connection was lost.' end
    if s.state=='local_transport_test' then return 'Developer socket-pair test: local only.' end
    if s.state=='overlay_unavailable' then return 'Enable Steam Overlay for this game, then restart the mod.' end
    if s.state=='steam_unavailable' then return 'Steam must be running and signed in.' end
    return 'Steam lobby could not be created. Please try again.'
end
return M
