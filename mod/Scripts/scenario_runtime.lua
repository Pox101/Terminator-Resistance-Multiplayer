-- Keep single-player gameplay classes on the host. Only base engine actors
-- cross the network; each process renders their installed character assets.
return function(H,C,emit)
    local mirrors,npcState,controlled={},nil,{}
    local preparedWorld,nextScan=0,0
    local function valid(o) return o~=nil and o:IsValid() end
    local function activeNpc(npc)
        return valid(npc) and npc:GetClass():GetFullName():find('Soldier',1,true)
            and valid(npc.HealthComponent) and type(npc.HealthComponent.Health)=='number'
    end
    local function prepare(pc)
        local world=pc:GetWorld()
        if preparedWorld~=world:GetAddress() then mirrors={};npcState=nil;nextScan=0;preparedWorld=world:GetAddress() end
        pc.Pawn:SetReplicates(false)
        local state=H.GetGameplayStatics():GetGameState(pc)
        if valid(state) then state.bReplicatedHasBegunPlay=false;state:SetReplicates(false) end
        for _,npc in ipairs(FindAllOf('AICharacter') or {}) do if activeNpc(npc) then npc:SetReplicates(false) end end
    end
    local function makeMirror(pc,source,playerState)
        local world=pc:GetWorld()
        local pawn=world:SpawnActor(StaticFindObject('/Script/Engine.Character'),source:K2_GetActorLocation(),source:K2_GetActorRotation())
        assert(valid(pawn),'Mirror spawn failed')
        pawn.CharacterMovement:DisableMovement();pawn:SetActorEnableCollision(false)
        pawn.CapsuleComponent:SetCollisionEnabled(0)
        pawn.bCanBeDamaged=false;pawn.bAlwaysRelevant=true;pawn.bNetUseOwnerRelevancy=false
        pawn.PlayerState=playerState;pawn.NetUpdateFrequency=10;pawn.MinNetUpdateFrequency=5
        pawn:SetReplicates(true);pawn:SetReplicateMovement(true);pawn:ForceNetUpdate()
        local pair={source=source,pawn=pawn};mirrors[#mirrors+1]=pair
        emit('scenario_mirror='..source:GetFullName())
        return pair
    end
    local function update(pc)
        if C.scenario~='infiltrator_hunt' or not valid(pc) or not valid(pc.Pawn) then return end
        local world=pc:GetWorld()
        if not world:GetFullName():find('LDLC1_Pasadena3_DLC1_ALL',1,true) then return end
        if C.role=='client' then
            -- Placed native NPCs have single-player callbacks; the host mirrors
            -- their authoritative state instead of running those callbacks here.
            for _,npc in ipairs(FindAllOf('AICharacter') or {}) do
                if activeNpc(npc) then npc:SetActorHiddenInGame(true);npc:SetActorEnableCollision(false);npc:SetActorTickEnabled(false) end
            end
            return
        end
        if not valid(world.NetDriver) then return end
        prepare(pc)
        if not valid(pc.PlayerState) then return end
        if not valid(npcState) then
            npcState=world:SpawnActor(StaticFindObject('/Script/Engine.PlayerState'),pc.Pawn:K2_GetActorLocation(),{Pitch=0,Yaw=0,Roll=0})
            npcState.PlayerId=1000000000;npcState.bAlwaysRelevant=true;npcState:ForceNetUpdate()
            pc.PlayerState:SetReplicates(false);pc.PlayerState:SetReplicates(true);pc.PlayerState:ForceNetUpdate()
            makeMirror(pc,pc.Pawn,pc.PlayerState)
        end
        local time=H.GetGameplayStatics():GetRealTimeSeconds(pc)
        if time>=nextScan then
            nextScan=time+1
            local known={};for _,pair in ipairs(mirrors) do if valid(pair.source) then known[pair.source:GetAddress()]=true end end
            for _,npc in ipairs(FindAllOf('AICharacter') or {}) do
                if #mirrors<17 and activeNpc(npc) and not npc.bHidden and npc.HealthComponent.Health>0 and not known[npc:GetAddress()] then
                    makeMirror(pc,npc,npcState)
                end
            end
        end
        for _,pair in ipairs(mirrors) do
            if valid(pair.pawn) then
                if valid(pair.source) then
                    pair.pawn:K2_SetActorLocation(pair.source:K2_GetActorLocation(),false,{},true)
                    pair.pawn:K2_SetActorRotation(pair.source:K2_GetActorRotation(),true)
                    pair.pawn.CharacterMovement.Velocity=pair.source:GetVelocity()
                    pair.pawn:SetActorHiddenInGame(controlled[pair.source:GetAddress()] or pair.source.bHidden or (activeNpc(pair.source) and pair.source.HealthComponent.Health<=0))
                else pair.pawn:SetActorHiddenInGame(true) end
            end
        end
        world.NetDriver.MaxClientRate=1000000;world.NetDriver.MaxInternetClientRate=1000000
        world.NetDriver.ClientConnections:ForEach(function(_,value)value:get().CurrentNetSpeed=1000000 end)
    end
    local api={prepare=prepare,update=update,setControlled=function(npc,active)controlled[npc:GetAddress()]=active~=false and true or nil end}
    _G.TRMPScenarioRuntime=api;return api
end
