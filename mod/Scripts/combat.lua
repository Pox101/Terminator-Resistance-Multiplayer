-- Local arena prototype. UE owns RPC routing; the host owns all combat state.
return function(H,C,emit,prototype,bodies)
    if C.scenario=='infiltrator_hunt' then return require('infiltrator_mission')(H,C,emit,prototype,bodies) end
    local Rules=require('combat_rules')
    local players,worldAddress,localView={},0,nil
    local mode=C.mode=='pvp' and 'pvp' or 'coop'
    local pendingRequests,fx={},{}
    local nextBroadcast,dirty,lastInput,lastReload=0,true,0,false
    local nativeProtected={}
    local function valid(o) return o~=nil and o:IsValid() end
    local function now(pc) return H.GetGameplayStatics():GetRealTimeSeconds(pc) end
    local function idFor(pc)
        if not valid(pc) or not valid(pc.PlayerState) then return nil end
        local id=pc.PlayerState.PlayerId
        if type(id)~='number' or id<0 or id%1~=0 then return nil end
        return id
    end
    local function eachPlayer()
        local ordered={};for _,p in pairs(players) do ordered[#ordered+1]=p end
        table.sort(ordered,function(a,b) return a.id<b.id end);return ordered
    end
    local function send(controller,message)
        if controller:IsLocalController() then
            localView=Rules.decode(message) or localView
            if localView then localView.receivedAt=now(controller) end
        else controller:ClientMessage(message,FName('TRMP1'),0) end
    end
    local function broadcast(time)
        local ordered=eachPlayer()
        for _,p in ipairs(ordered) do send(p.controller,Rules.encode(mode,p.id,ordered,time)) end
        dirty=false;nextBroadcast=time+1
    end
    local function event(message)
        for _,p in pairs(players) do
            if p.controller:IsLocalController() then fx[#fx+1]=message
            else p.controller:ClientMessage(message,FName('TRMP1'),0) end
        end
    end
    local function freeze(p,dead)
        if not valid(p.pawn) then return end
        if dead then
            p.pawn.CharacterMovement:DisableMovement()
            p.pawn.CharacterMovement:StopMovementImmediately()
        elseif p.frozen then
            p.pawn.CharacterMovement:SetMovementMode(1,0)
        end
        p.frozen=dead
    end
    local function shoot(p,time)
        local location=p.pawn:K2_GetActorLocation()
        local start={X=location.X,Y=location.Y,Z=location.Z+64}
        local rotation=p.controller:GetControlRotation()
        for _,v in ipairs({start.X,start.Y,start.Z,rotation.Pitch,rotation.Yaw}) do
            if type(v)~='number' or v~=v or math.abs(v)>1e7 then return end
        end
        local pitch,yaw=math.rad(rotation.Pitch),math.rad(rotation.Yaw)
        local direction={X=math.cos(pitch)*math.cos(yaw),Y=math.cos(pitch)*math.sin(yaw),Z=math.sin(pitch)}
        local finish={X=start.X+direction.X*Rules.range,Y=start.Y+direction.Y*Rules.range,Z=start.Z+direction.Z*Rules.range}
        local hit={}
        local blocked=H.GetKismetSystemLibrary():LineTraceSingle(p.pawn,start,finish,0,false,{},0,hit,true,
            {R=0,G=0,B=0,A=0},{R=0,G=0,B=0,A=0},0)
        local distance=blocked and math.min(Rules.range,hit.Distance+2) or Rules.range
        local target
        for _,other in pairs(players) do
            if other~=p and other.health>0 and valid(other.pawn) then
                local capsule=other.pawn.CapsuleComponent
                local t=Rules.rayCapsule(start,direction,other.pawn:K2_GetActorLocation(),
                    capsule:GetScaledCapsuleRadius(),capsule:GetScaledCapsuleHalfHeight(),distance)
                if t and t<distance then distance=t;target=other end
            end
        end
        local result='miss'
        if target then
            local applied,kind=Rules.damagePlayer(p,target,mode,time)
            result=kind
            if applied then
                emit(string.format('combat_damage=shooter:%d target:%d health:%d result:%s',p.id,target.id,target.health,kind))
                if target.health<=0 then freeze(target,true) end
            end
        end
        finish={X=start.X+direction.X*distance,Y=start.Y+direction.Y*distance,Z=start.Z+direction.Z*distance}
        event(string.format('TRMP1|F|%d|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%s',p.id,start.X,start.Y,start.Z,finish.X,finish.Y,finish.Z,result))
        emit(string.format('combat_shot=player:%d ammo:%d result:%s',p.id,p.ammo,result))
    end
    local function request(controller,action)
        if C.role~='host' or not valid(controller) or not valid(controller.Pawn) then return end
        local id=idFor(controller);local p=id and players[id]
        -- Match both UObject identity and possession. An old controller cannot
        -- act on a replacement player's state, even if a PlayerId is reused.
        if not p or p.controller:GetAddress()~=controller:GetAddress()
            or p.pawn:GetAddress()~=controller.Pawn:GetAddress() then return end
        local time=now(controller)
        -- Bound incoming work separately from the weapon's accepted fire rate.
        if time<(p.nextRequest or 0) then return end
        p.nextRequest=time+0.04
        local accepted,reason=Rules.request(p,action,time)
        if not accepted then
            if reason~='rate' and reason~='full' then emit('combat_rejected=player:'..id..' reason:'..reason) end
            return
        end
        if action=='fire' then shoot(p,time) else emit('combat_reload=player:'..id) end
        dirty=true
    end
    local function localRequest(pc,action)
        if C.role=='host' then request(pc,action)
        else pc:ServerCamera(FName(action=='fire' and 'TRMP1_FIRE' or 'TRMP1_RELOAD')) end
    end
    RegisterHook('/Script/Engine.PlayerController:ServerCamera',function(context,newMode)
        if C.role~='host' then return end
        local name=newMode:get():ToString()
        if name~='TRMP1_FIRE' and name~='TRMP1_RELOAD' and name~='TRMP1_SYNC' then return end
        local controller=context:get()
        if not valid(controller) or not valid(controller.Pawn) or controller:GetWorld():GetAddress()~=worldAddress then return end
        if name=='TRMP1_SYNC' then dirty=true;return end
        -- Requests contain only an action; origin, aim, hit, damage and ammo
        -- are reconstructed by the host from its actual replicated player.
        pendingRequests[#pendingRequests+1]={controller=controller,action=name=='TRMP1_FIRE' and 'fire' or 'reload'}
        if #pendingRequests>32 then table.remove(pendingRequests,1) end
    end)
    RegisterHook('/Script/Engine.PlayerController:ClientMessage',function(context,message,kind)
        if C.role~='client' or kind:get():ToString()~='TRMP1' then return end
        local controller=context:get()
        if not valid(controller) or not controller:IsLocalController() then return end
        local text=message:get():ToString()
        local state=Rules.decode(text)
        if state then
            state.receivedAt=now(controller)
            localView=state
        elseif #text<=256 and text:match('^TRMP1|F|') and #fx<32 then fx[#fx+1]=text end
        -- Native ClientMessage remains a display-only call, never an executor.
    end)
    local function add(controller)
        local pawn=controller.Pawn
        local id=idFor(controller)
        if not id or not valid(pawn) or not pawn:IsPlayerControlled() then return end
        if not pawn:IsLocallyControlled() and not prototype.isPlaced(pawn) then return end
        if players[id] and players[id].pawn:GetAddress()==pawn:GetAddress() then return end
        if #eachPlayer()>=Rules.maxPlayers then return end
        local faction=pawn:GetClass():GetFullName()=='Class /Script/Engine.Character' and 'terminator' or 'human'
        local p=Rules.newPlayer(id,faction)
        p.controller=controller;p.pawn=pawn;p.spawn=pawn:K2_GetActorLocation()
        players[id]=p;dirty=true
        -- Arena damage lives outside the single-player death/save pipeline.
        -- Native weapons cannot bypass the host's arena health decisions.
        nativeProtected[pawn:GetAddress()]={pawn=pawn,canBeDamaged=pawn.bCanBeDamaged}
        pawn.bCanBeDamaged=false
        if faction=='human' then
            local wc=pawn.WeaponComponent
            if valid(wc) then wc:StopShooting();wc:EnableNoWeaponMode(true,true) end
        end
        emit('combat_player='..id..' faction='..faction..' health='..p.health)
    end
    local function update(pc)
        if not valid(pc) or not valid(pc.Pawn) or not bodies.isReady(pc) then return end
        local world=pc:GetWorld()
        if world:GetAddress()~=worldAddress then
            worldAddress=world:GetAddress();players={};localView=nil;nativeProtected={}
            pendingRequests={};fx={};dirty=true;nextBroadcast=0
            lastInput=0;lastReload=false
            if C.role=='client' then pc:ServerCamera(FName('TRMP1_SYNC')) end
        end
        local time=now(pc)
        if C.role=='host' then
            for id,p in pairs(players) do
                if not valid(p.controller) or not valid(p.pawn) or not valid(p.controller.Pawn)
                    or p.controller.Pawn:GetAddress()~=p.pawn:GetAddress() then players[id]=nil;dirty=true end
            end
            for _,controller in ipairs(FindAllOf('PlayerController') or {}) do
                if valid(controller) and controller:GetWorld():GetAddress()==worldAddress then add(controller) end
            end
            for _,p in pairs(players) do
                local changed=Rules.advance(p,time)
                if changed then
                    dirty=true
                    if changed=='respawn' then
                        freeze(p,false)
                        p.pawn:K2_SetActorLocation(p.spawn,false,{},true)
                        p.controller:ClientSetLocation(p.spawn,p.controller:GetControlRotation())
                    end
                    emit('combat_'..changed..'=player:'..p.id)
                end
                if p.health<=0 then freeze(p,true) end
                p.pawn.bCanBeDamaged=false
            end
            local queued=pendingRequests;pendingRequests={}
            for _,r in ipairs(queued) do request(r.controller,r.action) end
            if dirty or time>=nextBroadcast then broadcast(time) end
        end
        bodies.setCombat(localView)
        for _,message in ipairs(fx) do bodies.shotEffect(pc,message) end
        fx={}
    end
    local function input(pc,state)
        if not valid(pc) or not valid(pc.Pawn) or not bodies.isReady(pc) then return end
        local time=now(pc)
        local focused,mask=prototype.isFocused()
        local fire=focused and math.floor(mask/32)%2==1
        local reload=focused and math.floor(mask/64)%2==1
        if fire and time>=lastInput then localRequest(pc,'fire');lastInput=time+Rules.interval end
        if reload and not lastReload then localRequest(pc,'reload') end
        lastReload=reload
    end
    -- Sample actual foreground input in the existing protected frame loop.
    -- Queued key callbacks can outlive a loading/menu context and its clock.
    local function command(pc,cmd)
        if cmd=='fire' or cmd=='reload' then localRequest(pc,cmd);return true end
        local newMode=cmd:match('^mode (%a+)$')
        if newMode then
            if C.role~='host' or (newMode~='coop' and newMode~='pvp') then return false end
            mode=newMode;dirty=true;emit('combat_mode='..mode);return true
        end
        if cmd=='combat-status' then
            if not localView then emit('combat_state=waiting');return true end
            for _,p in ipairs(localView.players) do
                emit(string.format('combat_state=mode:%s player:%d faction:%s health:%d/%d ammo:%d/%d kills:%d deaths:%d',
                    localView.mode,p.id,p.faction,p.health,p.maxHealth,p.ammo,p.reserve,p.kills,p.deaths))
            end
            return true
        end
        return false
    end
    local api={update=update,input=input,command=command,state=function() return localView end,
        players=function() return players end,request=request}
    _G.TRMPCombat=api
    return api
end
