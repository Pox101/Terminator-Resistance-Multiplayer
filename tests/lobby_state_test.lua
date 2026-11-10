return function(M)
    local n=0;local function check(ok)assert(ok);n=n+1 end
    local s=M.decode('TRMP_LOBBY1|lobby_ready|0|1|109775244000000001|0\n')
    check(s and s.lobby=='109775244000000001' and s.members==1 and not s.transport)
    check(M.message(s):find('1 / 2',1,true)~=nil)
    for _,bad in ipairs({'','TRMP_LOBBY1|unknown|0|1|1|0','TRMP_LOBBY1|idle|0|3|1|0',
        'TRMP_LOBBY1|idle|999999|1|1|0','TRMP_LOBBY1|idle|0|1|123456789012345678901|0',
        'TRMP_LOBBY1|idle|0|1|1|2','TRMP_LOBBY1|idle|0|1|1|0|extra'}) do check(M.decode(bad)==nil) end
    check(M.decode(nil)==nil)
    check(M.message({state='overlay_unavailable'}):find('Steam Overlay',1,true)~=nil)
    check(M.message({state='steam_unavailable'}):find('signed in',1,true)~=nil)
    return n
end
