-- A loopback-preview session provider. Its generation/state interface can be
-- backed by Steam lobby metadata when Internet game transport is available.
-- Native RestartGame is preserved; no quest/save/inventory flags are reset.
return function(H,C,emit,context)
    local Rules=require('session_rules')
    local path=C.directory..'/../trmp-session.txt'
    local state={run='',epoch=0,phase='menu',stamp=0}
    local worldAddress,gameModeAddress,lastWrite=0,0,0
    local restartStarted,previousEpoch=nil,0
    local attached,pending,joining,joinLoaded=nil,nil,false,false
    local function valid(o)return o~=nil and o:IsValid()end
    local function read()
        local f=io.open(path,'r');if not f then return end
        local value=f:read(161);f:close();return Rules.decode(value)
    end
    local function publish()
        state.stamp=os.time()
        local f=io.open(path,'w')
        if f then f:write(Rules.encode(state));f:close() end
        lastWrite=os.clock()
    end
    if C.role=='host' then
        local f=assert(io.open(C.directory..'/process-id.txt','r'));local pid=assert(tonumber(f:read('*a')));f:close()
        state.run=string.format('%d:%d',pid,os.time());publish()
        RegisterHook('/Script/Terminator.TerminatorGameMode:RestartGame',function(callback)
            if callback:get():GetAddress()~=gameModeAddress or restartStarted then return end
            previousEpoch=state.epoch;state.epoch=state.epoch+1;state.phase='restarting'
            restartStarted=os.clock();publish()
            emit('session_restart_requested='..state.epoch)
        end)
    end
    local function onTravel(reason)
        gameModeAddress=0;worldAddress=0
        if C.role=='host' and restartStarted and reason=='world_loaded' then
            restartStarted=nil;state.phase='loading';publish()
        elseif C.role=='client' and joining and reason=='world_loaded' then joinLoaded=true end
    end
    local function update()
        if C.role=='host' then
            -- During the native loading call there are no old-world gameplay
            -- reads. Post-load updates resume in the new standalone world.
            if restartStarted then
                if os.clock()-restartStarted>5 then
                    -- RestartGame may refuse while the native save manager is
                    -- busy. No map change occurred, so keep the same session.
                    restartStarted=nil;state.epoch=previousEpoch;state.phase='ready';publish()
                    emit('session_restart_cancelled=native_restart_did_not_travel')
                end
                return
            end
            local pc=context()
            if not valid(pc) or not valid(pc:GetWorld()) then return end
            local world=pc:GetWorld();local address=world:GetAddress()
            local mission=world:GetFullName():find('LDLC1_Pasadena3_DLC1_ALL',1,true)~=nil
            if worldAddress~=address then
                worldAddress=address
                if mission and state.phase~='loading' then state.epoch=state.epoch+1 end
            end
            local nextPhase=mission and (valid(world.NetDriver) and 'ready' or 'starting') or 'menu'
            local gm=mission and H.GetGameplayStatics():GetGameMode(pc) or nil
            gameModeAddress=valid(gm) and gm:GetAddress() or 0
            if state.phase~=nextPhase or os.clock()-lastWrite>=1 then state.phase=nextPhase;publish() end
            return
        end
        local marker=read();local decision=Rules.decision(attached,marker,os.time(),pending~=nil)
        if decision=='wait' then
            if not pending then emit('session_restart_waiting='..marker.epoch) end
            pending={run=marker.run,epoch=marker.epoch};joining=false;joinLoaded=false
        elseif decision=='cancel' then pending=nil;joining=false;joinLoaded=false
        elseif decision=='leave' then attached=nil;pending=nil;joining=false;joinLoaded=false
        elseif decision=='join' and not joining then
            local pc=context();if not valid(pc) then return end
            pending={run=marker.run,epoch=marker.epoch};joining=true;joinLoaded=false
            emit('session_restart_rejoin='..marker.epoch)
            H.GetKismetSystemLibrary():ExecuteConsoleCommand(pc,'open 127.0.0.1:7777',pc)
        end
    end
    local function observe(combatState)
        if C.role~='client' or not combatState or not combatState.you then return end
        if joining and not joinLoaded then return end
        local marker=read()
        if not marker or marker.phase~='ready' or os.time()-marker.stamp>15 then return end
        if pending and marker.epoch~=pending.epoch then return end
        if joining then emit('session_restart_connected='..marker.epoch) end
        attached={run=marker.run,epoch=marker.epoch};pending=nil;joining=false;joinLoaded=false
    end
    return {update=update,observe=observe,onTravel=onTravel,
        blocked=function()return C.role=='host' and restartStarted~=nil or C.role=='client' and pending~=nil and (not joining or not joinLoaded) end,
        joining=function()return joining end}
end
