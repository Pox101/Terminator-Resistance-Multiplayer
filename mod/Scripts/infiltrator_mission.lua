-- A remote input body drives an existing native bunker NPC. Its original
-- actor, team, weapon, health and quest/death bindings remain in the mission.
return function(H,C,emit,prototype,bodies)
    local Rules=require('mission_rules')
    local playerShot=require('npc_weapon')(H,emit)
    local effects={}
    local players,pending,view,worldAddress={}, {},nil,0
    local lastFire,lastReload,nextBroadcast=false,false,0
    local localControllerAddress=0
    local function valid(o) return o~=nil and o:IsValid() end
    local function nativeHealth(actor)
        return valid(actor) and valid(actor.HealthComponent) and actor.HealthComponent or nil
    end
    local function weapon(npc)
        return valid(npc) and valid(npc.WeaponComponent) and npc.WeaponComponent:GetCurrentWeapon(false) or nil
    end
    local function stop(p)
        if valid(p.native) and valid(p.native.WeaponComponent) then p.native.WeaponComponent:StopShooting() end
    end
    local function bunkerLocation()
        for _,a in ipairs(FindAllOf('B__DLC1_ObjectSpawner_AABASE_C') or {}) do
            if valid(a) and a:GetClass():GetFullName():find('TechComBunkerMAINQUEST',1,true) and a['Not Choosen']==false then return a:K2_GetActorLocation() end
        end
    end
    local function bind(controller)
        local bunker=bunkerLocation();local choices={}
        for _,npc in ipairs(FindAllOf('AICharacter') or {}) do
            local hp=nativeHealth(npc)
            if hp then
                local name=npc:GetClass():GetFullName()
                choices[#choices+1]={actor=npc,health=hp.Health,position=npc:K2_GetActorLocation(),
                    infantry=name:find('EnemySoldier',1,true)~=nil,commander=name:find('Commando',1,true)~=nil}
            end
        end
        local chosen=Rules.select(choices,bunker)
        if not chosen then return nil end
        local npc,pawn=chosen.actor,controller.Pawn
        npc.GameplayComponent:SpawnOwner(true)
        -- The single-player distance manager only follows the Infiltrator.
        -- Keep this one player-controlled slot awake while it is occupied.
        npc.GameplayComponent.bSpawnableOwner=false
        npc:SetActorTickEnabled(true);npc:SetActorHiddenInGame(false);npc:SetActorEnableCollision(true)
        npc.WeaponComponent:SetComponentTickEnabled(true)
        local gun=weapon(npc)
        if valid(gun) then
            gun:SetActorTickEnabled(true);gun:SetActorHiddenInGame(false)
            gun.bControlledByBTSShoot=false;gun.OptimizationConfig.bCanBeFullyOptimized=false
        end
        local ai=npc.Controller
        if valid(ai) and valid(ai.BrainComponent) then ai.BrainComponent:StopLogic('TRMP player takeover') end
        npc.WeaponComponent:StopShooting();npc.CharacterMovement:DisableMovement()
        if valid(npc.DespawnWithDistanceComponent) then npc.DespawnWithDistanceComponent.bOptimize=false;npc.DespawnWithDistanceComponent:SetComponentTickEnabled(false) end
        npc.CapsuleComponent:SetCollisionResponseToChannel(2,0)
        pawn.CapsuleComponent:SetCollisionResponseToAllChannels(0)
        pawn.CapsuleComponent:SetCollisionResponseToChannel(0,2);pawn.CapsuleComponent:SetCollisionResponseToChannel(1,2)
        pawn.CapsuleComponent:SetCollisionObjectType(1)
        -- The input capsule and original soldier occupy the same position.
        -- Ignore only that actor during movement sweeps; weapon traces still
        -- hit the original soldier and retain native hit/death handling.
        pawn.CapsuleComponent:IgnoreActorWhenMoving(npc,true)
        local pos=npc:K2_GetActorLocation();pawn:K2_SetActorLocation(pos,false,{},true)
        controller:ClientSetLocation(pos,npc:K2_GetActorRotation());pawn.CharacterMovement.MaxWalkSpeed=320
        if _G.TRMPScenarioRuntime then _G.TRMPScenarioRuntime.setControlled(npc) end
        emit('mission_takeover='..npc:GetFullName()..' controller:'..controller:GetFullName())
        return npc
    end
    RegisterHook('/Script/Engine.PlayerController:ServerCamera',function(context,action)
        if C.role~='host' then return end
        local name=action:get():ToString()
        if not ({TRMPM_FIREON=true,TRMPM_FIREOFF=true,TRMPM_RELOAD=true})[name] then return end
        local controller=context:get()
        if valid(controller) and #pending<32 then pending[#pending+1]={controller=controller,action=name} end
    end)
    RegisterHook('/Script/Engine.PlayerController:ClientMessage',function(context,message,kind)
        -- Do not call reflected native functions from inside an RPC hook:
        -- nested UE4SS calls can invalidate the callback registry.
        if C.role~='client' or kind:get():ToString()~='TRMPM' or context:get():GetAddress()~=localControllerAddress then return end
        local text=message:get():ToString();local state=Rules.decode(text)
        if state then view=state end
        if #text<=256 and text:match('^TRMP1|F|') and #effects<32 then effects[#effects+1]=text end
    end)
    local function update(pc)
        localControllerAddress=valid(pc) and pc:GetAddress() or 0
        if not valid(pc) or not valid(pc.Pawn) or not valid(pc:GetWorld().NetDriver)
            or not pc:GetWorld():GetFullName():find('LDLC1_Pasadena3_DLC1_ALL',1,true) then return end
        if C.role=='client' then
            bodies.setCombat(view)
            for _,effect in ipairs(effects) do bodies.shotEffect(pc,effect) end
            effects={};return
        end
        local world=pc:GetWorld();local time=H.GetGameplayStatics():GetRealTimeSeconds(pc)
        if worldAddress~=world:GetAddress() then players={};pending={};worldAddress=world:GetAddress() end
        for _,controller in ipairs(FindAllOf('PlayerController') or {}) do
            if valid(controller) and valid(controller.PlayerState) and valid(controller.Pawn) and controller:GetWorld():GetAddress()==worldAddress then
                local id=controller.PlayerState.PlayerId
                if not players[id] and (controller:IsLocalController() or prototype.isPlaced(controller.Pawn)) then
                    local npc=controller:IsLocalController() and controller.Pawn or bind(controller)
                    if npc then
                        local health=assert(nativeHealth(npc),'Native health missing')
                        players[id]={id=id,controller=controller,pawn=controller.Pawn,native=npc,faction=controller:IsLocalController() and 'terminator' or 'human',
                            health=math.ceil(health.Health),maxHealth=math.ceil(health.MaxHealth),ammo=0,nextRequest=0}
                        emit('mission_player='..id..' faction:'..players[id].faction..' native:'..npc:GetFullName())
                    end
                end
            end
        end
        for id,p in pairs(players) do
            if not valid(p.controller) or not valid(p.pawn) then
                stop(p)
                local hp=nativeHealth(p.native)
                if p.faction=='human' and hp and hp.Health>0 then
                    if valid(p.pawn) then p.pawn.CapsuleComponent:IgnoreActorWhenMoving(p.native,false) end
                    p.native.GameplayComponent.bSpawnableOwner=true;p.native.CharacterMovement:SetMovementMode(1,0)
                    if valid(p.native.Controller) and valid(p.native.Controller.BrainComponent) then p.native.Controller.BrainComponent:RestartLogic() end
                    if _G.TRMPScenarioRuntime then _G.TRMPScenarioRuntime.setControlled(p.native,false) end
                end
                players[id]=nil
            else
                local hp=nativeHealth(p.native);p.health=hp and math.max(0,math.ceil(hp.Health)) or 0
                if p.faction=='human' then
                    if p.health>0 then
                        if valid(p.native.Controller) and valid(p.native.Controller.BrainComponent) and not p.brainStopped then
                            p.native.Controller.BrainComponent:StopLogic('TRMP player takeover');p.brainStopped=true
                        end
                        p.native.CharacterMovement:DisableMovement()
                        p.native:K2_SetActorLocation(p.pawn:K2_GetActorLocation(),false,{},true)
                        local r=p.controller:GetControlRotation();p.native:K2_SetActorRotation({Pitch=0,Yaw=r.Yaw,Roll=0},true)
                        p.native.CharacterMovement.Velocity=p.pawn:GetVelocity()
                        if valid(p.native.Controller) then p.native.Controller:SetControlRotation(r) end
                        local pitch,yaw=math.rad(r.Pitch),math.rad(r.Yaw);local pos=p.pawn:K2_GetActorLocation()
                        local look=p.native.WeaponComponent:GetAssociatedLookAtComponent()
                        if valid(look) then look:ResetLookAtLocation({X=pos.X+math.cos(pitch)*math.cos(yaw)*20000,Y=pos.Y+math.cos(pitch)*math.sin(yaw)*20000,Z=pos.Z+64+math.sin(pitch)*20000}) end
                    else stop(p);p.pawn.CharacterMovement:DisableMovement() end
                    local gun=weapon(p.native)
                    if valid(gun) then p.ammo=math.max(0,math.min(10000,gun:GetCurrentAmmoInClip())) end
                end
            end
        end
        local requests=pending;pending={}
        for _,request in ipairs(requests) do
            local controller=request.controller
            if valid(controller) and valid(controller.PlayerState) then
                local p=players[controller.PlayerState.PlayerId]
                if p and p.faction=='human' and p.controller:GetAddress()==controller:GetAddress() and p.pawn:GetAddress()==controller.Pawn:GetAddress() and p.health>0 then
                    if request.action=='TRMPM_FIREOFF' then p.firing=false;stop(p)
                    elseif time>=p.nextRequest then
                        p.nextRequest=time+0.04
                        if request.action=='TRMPM_FIREON' then p.firing=true
                        elseif request.action=='TRMPM_RELOAD' then p.native.WeaponComponent:Reload() end
                    end
                end
            end
        end
        local target
        for _,p in pairs(players) do if p.faction=='terminator' then target=p end end
        for _,p in pairs(players) do
            if p.faction=='human' and p.firing and p.health>0 then
                local effect=playerShot(p,target,time)
                if effect then p.controller:ClientMessage(effect,FName('TRMPM'),0) end
            end
        end
        if time>=nextBroadcast then
            nextBroadcast=time+0.25;local ordered={}
            for _,p in pairs(players) do ordered[#ordered+1]=p end
            table.sort(ordered,function(a,b)return a.id<b.id end)
            for _,p in ipairs(ordered) do
                if not p.controller:IsLocalController() then p.controller:ClientMessage(Rules.encode(p.id,ordered),FName('TRMPM'),0) end
            end
        end
    end
    local function input(pc)
        if C.role~='client' or not valid(pc) or not valid(pc.Pawn) or not bodies.isReady(pc) then return end
        local focus,mask=prototype.isFocused();local fire=focus and math.floor(mask/32)%2==1
        local reload=focus and math.floor(mask/64)%2==1
        if fire~=lastFire then pc:ServerCamera(FName(fire and 'TRMPM_FIREON' or 'TRMPM_FIREOFF'));lastFire=fire end
        if reload and not lastReload then pc:ServerCamera(FName('TRMPM_RELOAD')) end
        lastReload=reload
    end
    local function command(pc,cmd)
        if cmd=='fire' then pc:ServerCamera(FName('TRMPM_FIREON'));return true end
        if cmd=='stop-fire' then pc:ServerCamera(FName('TRMPM_FIREOFF'));return true end
        if cmd=='reload' then pc:ServerCamera(FName('TRMPM_RELOAD'));return true end
        if cmd=='combat-status' or cmd=='round-status' then
            for _,p in pairs(players) do emit('mission_state='..p.id..' faction:'..p.faction..' health:'..p.health..' native:'..p.native:GetFullName()) end
            return true
        end
        return false
    end
    local api={update=update,input=input,command=command,state=function()return view end,players=function()return players end,mission=function()return true end}
    _G.TRMPCombat=api;return api
end
