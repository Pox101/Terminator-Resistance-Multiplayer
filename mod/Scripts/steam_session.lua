-- Experimental Steam party control. All console destinations are fixed local
-- endpoints: no lobby text is ever interpolated into an engine command.
return function(H,C,emit,context,changeRole)
    local Lobby=require('lobby_state')
    local Session=require('session_rules')
    local api,state,nextPoll={},nil,0
    local initialJoin,party,testStarted,aborted=false,nil,false,false
    for _,name in ipairs({'initialize','create','poll','accept','leave','frame','publish_session','test_tunnel'}) do
        api[name]=assert(package.loadlib(C.directory..'/steam_lobby.dll','lobby_'..name))
    end
    local function valid(o)return o~=nil and o:IsValid()end
    local function read(name,limit)
        local f=io.open(C.directory..'/'..name,'r');if not f then return end
        local text=f:read(limit+1);f:close();if #text<=limit then return text end
    end
    local function command(pc,text)H.GetKismetSystemLibrary():ExecuteConsoleCommand(pc,text,pc)end
    api.initialize()
    local function host()
        changeRole('host');initialJoin=false;party=nil;aborted=false;api.create()
    end
    local function leave()
        initialJoin=false;party=nil;aborted=false;api.leave()
    end
    local function update()
        local now=os.clock();if now<nextPoll then return end;nextPoll=now+0.2
        api.poll();state=Lobby.decode(read('steam-lobby-state.txt',160)) or state
        if C.transport=='tunnel_test' then
            if C.role=='host' and not testStarted then api.test_tunnel();testStarted=true;emit('steam_socket_pair_test_started=local_only') end
            return
        end
        if not state then return end
        local pc=context();if not valid(pc) then return end
        local inMenu=pc:GetWorld():GetFullName():find('MAP_StartingMap',1,true)~=nil
        if state.state=='invitation_pending' then
            -- Accepted invitations received during an active mission wait for
            -- the native menu; the game is not torn down inside a callback.
            if inMenu then changeRole('client');initialJoin=false;party=nil;aborted=false;api.accept() end
        elseif state.state=='owner_left' or state.state=='peer_disconnected' or state.state=='transport_failed' or state.state=='incompatible' then
            api.leave();initialJoin=false;party=nil
            if not inMenu and not aborted then
                aborted=true;emit('steam_party_ended='..state.state)
                command(pc,'open /Game/Maps/MAP_StartingMap')
                return true
            end
        elseif state.transport and C.role=='client' and not initialJoin then
            local marker=Session.decode(read('steam-session-state.txt',160))
            if marker and marker.phase=='ready' and os.time()-marker.stamp<=15 and marker.stamp<=os.time()+10 then
                initialJoin=true;party=state.lobby
                emit('steam_initial_game_join=relay_tunnel')
                command(pc,'open 127.0.0.1:7778')
                return true
            end
        end
    end
    return {update=update,frame=api.frame,host=host,leave=leave,
        publish=api.publish_session,state=function()return state end}
end
