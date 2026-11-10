return function(factory,Lobby,Session)
    local n=0;local function check(ok,label)assert(ok,label);n=n+1 end
    local original={open=io.open,loadlib=package.loadlib,clock=os.clock,time=os.time,lobby=package.loaded.lobby_state,session=package.loaded.session_rules}
    local files,commands,calls={}, {},{}
    local now,stamp=0,1800000000
    local config={directory='test',role='host',transport='steam'}
    local worldName='World /Game/Maps/MAP_StartingMap.MAP_StartingMap'
    local pc={IsValid=function()return true end,GetWorld=function()return {GetFullName=function()return worldName end}end}
    package.loaded.lobby_state=Lobby;package.loaded.session_rules=Session
    os.clock=function()return now end;os.time=function()return stamp end
    io.open=function(path)
        local value=files[path:match('[^/]+$')];if not value then return end
        return {read=function()return value end,close=function()end}
    end
    package.loadlib=function(_,name)return function()calls[name]=(calls[name] or 0)+1 end end
    local ok,err=pcall(function()
        local api=factory({GetKismetSystemLibrary=function()return {ExecuteConsoleCommand=function(_,_,text)commands[#commands+1]=text end}end},config,function()end,function()return pc end,function(role)config.role=role end)
        check(calls.lobby_initialize==1,'receiver registers callbacks without opening Play Versus')
        local function tick(state,transport)
            files['steam-lobby-state.txt']='TRMP_LOBBY1|'..state..'|0|2|123|'..(transport and '1' or '0')
            now=now+0.3;return api.update()
        end
        worldName='World /Game/Maps/DLC1/LDLC1_Pasadena3_DLC1_ALL.LDLC1_Pasadena3_DLC1_ALL'
        tick('invitation_pending');check(not calls.lobby_accept,'active mission is never torn down by a callback')
        worldName='World /Game/Maps/MAP_StartingMap.MAP_StartingMap';tick('invitation_pending')
        check(config.role=='client' and calls.lobby_accept==1,'accepted invite changes menu instance to defender before joining')
        files['steam-session-state.txt']=Session.encode({run='99:1800000000',epoch=1,phase='ready',stamp=stamp})
        tick('transport_connecting');check(#commands==0,'no engine join before authenticated relay handshake')
        files['steam-session-state.txt']=Session.encode({run='99:1800000000',epoch=1,phase='loading',stamp=stamp})
        tick('transport_ready',true);check(#commands==0,'wait through original host loading and intro')
        files['steam-session-state.txt']=Session.encode({run='99:1800000000',epoch=1,phase='ready',stamp=stamp-16})
        tick('transport_ready',true);check(#commands==0,'stale ready metadata does not launch game travel')
        files['steam-session-state.txt']=Session.encode({run='99:1800000000',epoch=1,phase='ready',stamp=stamp})
        check(tick('transport_ready',true)==true,'initial travel stops old-world gameplay reads')
        check(#commands==1 and commands[1]=='open 127.0.0.1:7778','game connects only through fixed local relay proxy')
        tick('transport_ready',true);check(#commands==1,'one initial engine join per party')
        api.frame();check(calls.lobby_frame==1,'data pump remains separate from lobby polling')
        worldName='World /Game/Maps/DLC1/LDLC1_Pasadena3_DLC1_ALL.LDLC1_Pasadena3_DLC1_ALL'
        check(tick('owner_left')==true,'disconnect travel stops old-world gameplay reads')
        tick('owner_left');check(#commands==2 and commands[2]=='open /Game/Maps/MAP_StartingMap','disconnect ends the game once')
        api.host();check(config.role=='host' and calls.lobby_create==1,'same menu instance can host a new party')
        local previousLeaves=calls.lobby_leave or 0
        api.leave();check(calls.lobby_leave==previousLeaves+1,'leaving explicitly cancels party state')
    end)
    io.open=original.open;package.loadlib=original.loadlib;os.clock=original.clock;os.time=original.time
    package.loaded.lobby_state=original.lobby;package.loaded.session_rules=original.session
    assert(ok,err);return n
end
