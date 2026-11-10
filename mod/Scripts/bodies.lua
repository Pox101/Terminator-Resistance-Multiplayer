-- Local cosmetic actors follow the real replicated pawns on each machine.
-- They never replace possession, movement replication, or the saved game pawn.
return function(H,C,emit,prototype)
    local Scenario=require('scenario_rules')
    local bodies, assets = {}, {}
    local worldAddress, readyAfter, nextUpdate = 0, 0, 0
    local camera, cameraPawn, thirdPerson, vision = nil, nil, true, false
    local reticle, reticlePawn, lastFrame = nil, nil, nil
    local currentFov, aiming = 85, false
    local cameraFocused=false
    local combatView,hud,hudText,fpWeapon,fpPawn=nil,nil,nil,nil,nil
    local hudValue,recoilUntil,deadInput='',0,false
    local effectDefaults
    local hostAim,hostFov=nil,nil
    local assetOwner
    local function retain(object)
        -- Lua handles do not keep Unreal assets alive across garbage collection.
        -- One rooted engine referencer per asset avoids UE4SS 3.0.1's TArray
        -- append bug. These few installed assets stay loaded for this process.
        _G.TRMPAssetRoots=_G.TRMPAssetRoots or {}
        local key=object:GetFullName()
        if not _G.TRMPAssetRoots[key] then
            local holder=StaticConstructObject(StaticFindObject('/Script/Engine.ObjectReferencer'),assetOwner,FName('None'),0x80)
            assert(holder:IsValid() and holder:HasAnyInternalFlags(0x40000000),'Asset referencer is not rooted')
            holder.ReferencedObjects[1]=object
            assert(holder.ReferencedObjects:GetArrayNum()==1 and holder.ReferencedObjects[1]:GetAddress()==object:GetAddress(),
                'Could not retain cosmetic asset')
            _G.TRMPAssetRoots[key]=holder
        end
        return object
    end
    local stage, created, retryAfter = 'waiting', {}, 0
    local function valid(o) return o~=nil and o:IsValid() end
    local paths = {
        terminator='/Game/Meshes/Characters/DLC1/CutsceneFranco/SK_Franco_Infiltrator.SK_Franco_Infiltrator',
        terminatorRig='/Game/Meshes/Characters/T800Skin/SK_T800Skin.SK_T800Skin',
        human='/Game/Meshes/Characters/DLC1/ResistanceSoldiers/SK_ResistanceSoldier01.SK_ResistanceSoldier01',
        terminatorIdle='/Game/Animations/T800Skin/T800SkinMinigun/Sequences/A_T800SkinMinigunIdle.A_T800SkinMinigunIdle',
        terminatorWalk='/Game/Animations/T800Skin/T800SkinMinigun/Sequences/A_T800SkinMinigunWalk.A_T800SkinMinigunWalk',
        humanIdle='/Game/Animations/FriendlyAI/FriendlySoldier/Sequences/A_FriendlyAIIdleNormal.A_FriendlyAIIdleNormal',
        humanWalk='/Game/Animations/FriendlyAI/FriendlySoldier/Sequences/A_FriendlyAIPlasmaRelaxWalkFwdLoop.A_FriendlyAIPlasmaRelaxWalkFwdLoop',
        vision='/Game/Materials/DLC1/Characters/M_InfiltratorVisionPostprocessTest_Inst.M_InfiltratorVisionPostprocessTest_Inst',
        weapon='/Game/Meshes/Weapons/Plasma/SK_Plasma.SK_Plasma',
        worldWeapon='/Game/Meshes/Weapons/Plasma/SK_PlasmaNPC.SK_PlasmaNPC',
        plasmaClass='/Game/Blueprints/Weapons/WP_PlasmaR.WP_PlasmaR'
    }
    local function asset(name)
        if valid(assets[name]) then return assets[name] end
        local object=StaticFindObject(paths[name])
        if not valid(object) then LoadAsset(paths[name]); object=StaticFindObject(paths[name]) end
        assert(valid(object),'Missing body asset: '..paths[name])
        assets[name]=retain(object)
        return object
    end
    local initialize=assert(package.loadlib(C.directory..'/prototype_runtime.dll','initialize_local'))
    local function beginEngineActor(actor)
        local class=actor:GetClass()
        local name=class:GetFullName()
        assert(name=='Class /Script/Engine.SkeletalMeshActor' or name=='Class /Script/Engine.CameraActor')
        local pidFile=assert(io.open(C.directory..'/process-id.txt','r'))
        local pid=assert(tonumber(pidFile:read('*a')));pidFile:close()
        local file=assert(io.open(C.directory..'/prototype-actors.txt','w'))
        file:write(string.format('%d %X %X %X %X',pid,actor:GetAddress(),class:GetAddress(),actor:GetAddress(),class:GetAddress()))
        file:close();initialize()
    end
    local function spawn(pc,className)
        stage='spawn '..className
        -- The UE4SS UWorld wrapper marshals the deferred-spawn transform.
        local actor=pc:GetWorld():SpawnActor(StaticFindObject('/Script/Engine.'..className),pc.Pawn:K2_GetActorLocation(),{Pitch=0,Yaw=0,Roll=0})
        assert(valid(actor),'Could not spawn '..className)
        created[#created+1]=actor
        actor:SetOwner(pc.Pawn)
        actor:SetReplicates(false)
        actor:SetActorEnableCollision(false)
        beginEngineActor(actor)
        return actor
    end
    local function attach(actor,pawn,z,yaw)
        actor:K2_AttachToComponent(pawn.RootComponent,FName('None'),2,2,2,false)
        actor:K2_SetActorRelativeLocation({X=0,Y=0,Z=z},false,{},true)
        actor:K2_SetActorRelativeRotation({Pitch=0,Yaw=yaw,Roll=0},false,{},true)
    end
    local function setupBody(pc,pawn,kind)
        local actor=spawn(pc,'SkeletalMeshActor')
        stage='configure '..kind..' mesh'
        actor:SetOwner(pawn)
        local mesh=actor.SkeletalMeshComponent
        mesh:SetSkeletalMesh(asset(kind),true)
        mesh:SetCollisionEnabled(0)
        mesh:SetVisibility(true,true)
        mesh:SetHiddenInGame(false,true)
        mesh:SetOwnerNoSee(pawn:IsLocallyControlled() and (kind=='human' or not thirdPerson))
        attach(actor,pawn,-pawn.CapsuleComponent:GetScaledCapsuleHalfHeight(),-90)
        local poseMesh,driver=mesh,nil
        if kind=='terminator' then
            -- The cutscene body has extra face bones. Drive its shared body
            -- bones from the shipped gameplay skeleton instead of assigning
            -- incompatible animation assets to the cutscene skeleton.
            driver=spawn(pc,'SkeletalMeshActor')
            stage='configure terminator pose driver'
            poseMesh=driver.SkeletalMeshComponent
            poseMesh:SetSkeletalMesh(asset('terminatorRig'),true)
            poseMesh.VisibilityBasedAnimTickOption=0
            poseMesh:SetHiddenInGame(true,true)
            attach(driver,pawn,-pawn.CapsuleComponent:GetScaledCapsuleHalfHeight(),-90)
            mesh:SetMasterPoseComponent(poseMesh,true)
        end
        local body={actor=actor,driver=driver,pawn=pawn,mesh=mesh,poseMesh=poseMesh,kind=kind,moving=nil}
        if C.combatEnabled then
            local weapon=spawn(pc,'SkeletalMeshActor')
            weapon:SetOwner(pawn)
            weapon.SkeletalMeshComponent:SetSkeletalMesh(asset('worldWeapon'),true)
            weapon.SkeletalMeshComponent:SetCollisionEnabled(0)
            local socket=mesh:DoesSocketExist(FName('Weapon_socket')) and 'Weapon_socket' or 'hand_r'
            weapon:K2_AttachToComponent(mesh,FName(socket),2,2,2,false)
            body.weapon=weapon
        end
        bodies[pawn:GetAddress()]=body
        emit('player_body='..kind..' pawn='..pawn:GetFullName()..' mesh='..asset(kind):GetFullName())
        return body
    end
    local function setupCamera(pc)
        if valid(camera) and valid(cameraPawn) and cameraPawn:GetAddress()==pc.Pawn:GetAddress() then return end
        camera=spawn(pc,'CameraActor');cameraPawn=pc.Pawn
        local state=_G.TRMPCombat and _G.TRMPCombat.state()
        if C.mode=='pvp' or (state and state.mode=='pvp') then thirdPerson=false end
        cameraFocused=false
        attach(camera,pc.Pawn,90,0)
        camera:K2_SetActorRelativeLocation({X=thirdPerson and -350 or 0,Y=thirdPerson and -150 or 0,Z=thirdPerson and 100 or 64},false,{},true)
        camera:K2_SetActorRelativeRotation({Pitch=thirdPerson and -12 or 0,Yaw=thirdPerson and 23 or 0,Roll=0},false,{},true)
        camera.CameraComponent:SetFieldOfView(85)
        pc:SetViewTargetWithBlend(camera,0,0,0,false)
        emit('terminator_camera=third_person F5=view V=infiltrator_vision')
    end
    local function setupReticle(pc)
        if valid(reticle) and valid(reticlePawn) and reticlePawn:GetAddress()==pc.Pawn:GetAddress() then return end
        if valid(reticle) then reticle:RemoveFromParent() end
        local path='/Game/UI/Globals/WB_Empty.WB_Empty'
        LoadAsset(path)
        retain(StaticFindObject(path..'_C'))
        reticle=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(pc,StaticFindObject(path..'_C'),pc)
        assert(valid(reticle),'Could not create aim reticle')
        reticlePawn=pc.Pawn
        local root=StaticConstructObject(StaticFindObject('/Script/UMG.CanvasPanel'),reticle.WidgetTree)
        reticle.WidgetTree.RootWidget=root
        local text=StaticConstructObject(StaticFindObject('/Script/UMG.TextBlock'),reticle.WidgetTree)
        text:SetText(StaticFindObject('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText('+'))
        local slot=root:AddChildToCanvas(text)
        slot.LayoutData.Anchors.Minimum={X=0.5,Y=0.5}
        slot.LayoutData.Anchors.Maximum={X=0.5,Y=0.5}
        slot:SetAlignment({X=0.5,Y=0.5})
        slot:SetPosition({X=0,Y=0});slot:SetAutoSize(true)
        reticle:SetVisibility(3)
        reticle:AddToViewport(100)
        emit('aim_reticle=created')
    end
    local function frame(pc,input)
        if C.role~='client' or not valid(camera) or not valid(cameraPawn)
            or not valid(pc) or not valid(pc.Pawn) or cameraPawn:GetAddress()~=pc.Pawn:GetAddress() then return end
        local now=H.GetGameplayStatics():GetRealTimeSeconds(pc)
        if lastFrame==now then return end
        local dt=lastFrame and math.max(0,math.min(now-lastFrame,0.1)) or 0
        lastFrame=now
        local focused=input and input.focused or false
        if focused and not cameraFocused then
            -- Loading/menu code can replace the input mode after possession.
            -- Restore capture once the camera is ready, and on focus regain.
            StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):SetInputMode_GameOnly(pc)
            pc.bShowMouseCursor=false;pc:ResetIgnoreLookInput();pc:ResetIgnoreMoveInput()
            pc.PlayerInput:ClearSmoothing()
            emit('camera_mouse_capture=ready')
        end
        cameraFocused=focused
        local wantsAim=input and input.aiming or false
        if wantsAim~=aiming then aiming=wantsAim;emit('aiming='..tostring(aiming)) end
        local targetFov=aiming and 55 or 85
        currentFov=currentFov+(targetFov-currentFov)*math.min(1,dt*14)
        camera.CameraComponent:SetFieldOfView(currentFov)
        local r=pc:GetControlRotation()
        local yaw,pitch=math.rad(r.Yaw),math.rad(r.Pitch)
        local origin=pc.Pawn:K2_GetActorLocation()
        local eye={X=origin.X,Y=origin.Y,Z=origin.Z+64}
        local position=eye
        if thirdPerson then
            local distance=aiming and 210 or 300
            position={X=eye.X-math.cos(pitch)*math.cos(yaw)*distance-math.sin(yaw)*55,
                Y=eye.Y-math.cos(pitch)*math.sin(yaw)*distance+math.cos(yaw)*55,
                Z=eye.Z-math.sin(pitch)*distance+20}
            local hit={}
            -- IgnoreSelf resolves the world-context actor, so pass the pawn.
            if H.GetKismetSystemLibrary():LineTraceSingle(pc.Pawn,eye,position,0,false,{},0,hit,true,
                {R=0,G=0,B=0,A=0},{R=0,G=0,B=0,A=0},0) then
                local p,n=hit.ImpactPoint,hit.ImpactNormal
                position={X=p.X+n.X*12,Y=p.Y+n.Y*12,Z=p.Z+n.Z*12}
            end
        end
        local body=bodies[pc.Pawn:GetAddress()]
        if body then
            local dx,dy,dz=position.X-eye.X,position.Y-eye.Y,position.Z-eye.Z
            body.cameraHidden=dx*dx+dy*dy+dz*dz<110*110
            body.mesh:SetHiddenInGame(not thirdPerson or dx*dx+dy*dy+dz*dz<110*110,true)
        end
        camera:K2_SetActorLocation(position,false,{},true)
        camera:K2_SetActorRotation({Pitch=r.Pitch,Yaw=r.Yaw,Roll=0},true)
    end
    local function command(pc,name)
        if C.role~='client' or not valid(pc) or not valid(pc.Pawn)
            or pc.Pawn:GetClass():GetFullName()~='Class /Script/Engine.Character' or not valid(camera) then return end
        if name=='view' then
            if combatView and combatView.mode=='pvp' then emit('view_rejected=pvp_first_person_only');return end
            thirdPerson=not thirdPerson
            pc:SetViewTargetWithBlend(camera,0,0,0,false)
            local body=bodies[pc.Pawn:GetAddress()]
            if body then body.mesh:SetHiddenInGame(not thirdPerson,true) end
            emit('third_person='..tostring(thirdPerson))
            lastFrame=nil
            frame(pc,nil)
        elseif name=='vision' then
            vision=not vision
            camera.CameraComponent:AddOrUpdateBlendable(asset('vision'),vision and 1.0 or 0.0)
            local settings=camera.CameraComponent.PostProcessSettings
            settings.bOverride_ColorSaturation=vision
            settings.ColorSaturation={X=0,Y=0,Z=0,W=1}
            settings.bOverride_ColorGain=vision
            settings.ColorGain={X=1,Y=0.08,Z=0.04,W=1}
            emit('infiltrator_vision='..tostring(vision))
        end
    end
    for key,name in pairs({F5='view',V='vision'}) do
        RegisterKeyBind(Key[key],function()
            ExecuteInGameThread(function()
                local ok,err=pcall(function()
                    if not prototype.isFocused() then return end
                    local engine=FindFirstOf('GameEngine')
                    command(H.GetGameplayStatics():GetPlayerController(engine.GameViewport,0),name)
                end)
                if not ok then emit('body_key_error='..tostring(err)) end
            end)
        end)
    end
    local function update(pc)
        if C.scenario=='infiltrator_hunt' and C.role=='host' then return end
        stage='check world'
        if not valid(pc) or not valid(pc.Pawn) then return end
        local world=pc:GetWorld()
        local name=world:GetFullName()
        if name:find('MAP_StartingMap') or name:lower():find('menu') then return end
        if not valid(world.NetDriver) then return end
        if world:GetAddress()~=worldAddress then
            if valid(reticle) then reticle:RemoveFromParent() end
            worldAddress=world:GetAddress();bodies={};camera=nil;cameraPawn=nil
            reticle=nil;reticlePawn=nil;lastFrame=nil;currentFov=85;aiming=false
            hud=nil;hudText=nil;fpWeapon=nil;fpPawn=nil;combatView=nil;effectDefaults=nil;hudValue='';deadInput=false
            nextUpdate=0;retryAfter=0;thirdPerson=true;vision=false
            readyAfter=os.time()+12
        end
        local game=H.GetGameplayStatics():GetGameInstance(pc)
        if game.bIsInLoadingScreen or (C.scenario=='infiltrator_hunt' and game.bIsInCutscene) then readyAfter=os.time()+12;return end
        if C.scenario=='infiltrator_hunt' and not name:find('LDLC1_Pasadena3_DLC1_ALL',1,true) then return end
        if os.time()<readyAfter then return end
        assetOwner=game
        stage='read world time'
        local now=H.GetGameplayStatics():GetRealTimeSeconds(pc)
        if now<nextUpdate then return end
        nextUpdate=now+0.15
        for address,body in pairs(bodies) do
            if not valid(body.pawn) or not valid(body.actor) then
                if valid(body.actor) then body.actor:K2_DestroyActor() end
                if valid(body.driver) then body.driver:K2_DestroyActor() end
                if valid(body.weapon) then body.weapon:K2_DestroyActor() end
                bodies[address]=nil
            end
        end
        for _,pawn in ipairs(FindAllOf('Pawn') or {}) do
            local mirror=C.scenario=='infiltrator_hunt' and valid(pawn) and C.role=='client'
                and pawn:GetClass():GetFullName()=='Class /Script/Engine.Character' and not pawn:IsLocallyControlled() and valid(pawn.PlayerState)
            local controlled=valid(pawn) and pawn:IsPlayerControlled() and (C.scenario~='infiltrator_hunt' or valid(pawn.Controller))
            if valid(pawn) and (controlled or mirror) and pawn:GetWorld():GetAddress()==worldAddress then
                local kind=mirror and (pawn.PlayerState.PlayerId==1000000000 and 'human' or 'terminator')
                    or Scenario.faction(pawn:GetClass():GetFullName(),C.scenario)
                if not kind then return end
                local body=bodies[pawn:GetAddress()] or setupBody(pc,pawn,kind)
                local velocity=pawn:GetVelocity()
                local moving=velocity.X*velocity.X+velocity.Y*velocity.Y>25
                if body.moving~=moving then
                    stage='animate '..kind
                    body.poseMesh:PlayAnimation(asset(kind..(moving and 'Walk' or 'Idle')),true)
                    body.moving=moving
                    emit('body_animation='..kind..(moving and '_walk' or '_idle'))
                end
                if kind=='terminator' then
                    -- Walking speed read from the shipped CH_FPPInfiltrator CDO.
                    pawn.CharacterMovement.MaxWalkSpeed=320.0
                end
                if C.role=='client' and pawn:IsLocallyControlled() then setupCamera(pc);setupReticle(pc) end
            end
        end
    end
    local function safeUpdate(pc)
        if os.time()<retryAfter then return end
        created={}
        local ok,err=pcall(update,pc)
        if not ok then
            for _,actor in ipairs(created) do if valid(actor) then pcall(function() actor:K2_DestroyActor() end) end end
            retryAfter=os.time()+5
            emit('body_error='..stage..' '..tostring(err))
        end
        created={}
    end
    local function dispose()
        if valid(hud) then hud:RemoveFromParent() end
        if valid(fpWeapon) then fpWeapon:K2_DestroyActor() end
        if valid(reticle) then reticle:RemoveFromParent() end
        if valid(camera) then camera:K2_DestroyActor() end
        for _,body in pairs(bodies) do
            if valid(body.actor) then body.actor:K2_DestroyActor() end
            if valid(body.driver) then body.driver:K2_DestroyActor() end
            if valid(body.weapon) then body.weapon:K2_DestroyActor() end
        end
        bodies={};camera=nil;cameraPawn=nil;reticle=nil;reticlePawn=nil
    end
    local function isReady(pc)
        return valid(pc) and valid(pc.Pawn) and pc:GetWorld():GetAddress()==worldAddress
            and os.time()>=readyAfter and bodies[pc.Pawn:GetAddress()]~=nil
    end
    local function setCombat(state)
        combatView=state
        if state and state.mode=='pvp' then thirdPerson=false end
    end
    local function setupCombat(pc)
        if not valid(reticle) then setupReticle(pc) end
        if not valid(hud) then
            local path='/Game/UI/Globals/WB_Empty.WB_Empty'
            local class=StaticFindObject(path..'_C')
            if not valid(class) then LoadAsset(path);class=StaticFindObject(path..'_C') end
            retain(class)
            hud=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(pc,class,pc)
            local root=StaticConstructObject(StaticFindObject('/Script/UMG.CanvasPanel'),hud.WidgetTree)
            hud.WidgetTree.RootWidget=root
            hudText=StaticConstructObject(StaticFindObject('/Script/UMG.TextBlock'),hud.WidgetTree)
            hudText.Font.Size=24
            local slot=root:AddChildToCanvas(hudText)
            slot:SetPosition({X=30,Y=30});slot:SetAutoSize(true)
            hud:SetVisibility(3);hud:AddToViewport(110)
        end
        if not valid(fpWeapon) or not valid(fpPawn) or fpPawn:GetAddress()~=pc.Pawn:GetAddress() then
            fpWeapon=spawn(pc,'SkeletalMeshActor');fpPawn=pc.Pawn
            fpWeapon.SkeletalMeshComponent:SetSkeletalMesh(asset('weapon'),true)
            fpWeapon.SkeletalMeshComponent:SetCollisionEnabled(0)
            local component=C.role=='client' and camera.CameraComponent or pc.Pawn.Camera
            fpWeapon:K2_AttachToComponent(component,FName('None'),2,2,2,false)
            fpWeapon:K2_SetActorRelativeLocation({X=38,Y=13,Z=-19},false,{},true)
            fpWeapon:K2_SetActorRelativeRotation({Pitch=0,Yaw=-90,Roll=90},false,{},true)
        end
        if not effectDefaults then
            local path=paths.plasmaClass
            local class=StaticFindObject(path..'_C')
            if not valid(class) then LoadAsset(path);class=StaticFindObject(path..'_C') end
            if valid(class) then
                retain(class);effectDefaults=class:GetCDO()
                if valid(effectDefaults.MuzzleFX) then retain(effectDefaults.MuzzleFX) end
                if valid(effectDefaults.ShotSound) then retain(effectDefaults.ShotSound) end
            end
        end
    end
    local function combatFrame(pc)
        if C.scenario=='infiltrator_hunt' and C.role=='host' then return end
        if not C.combatEnabled or not isReady(pc) then return end
        assetOwner=H.GetGameplayStatics():GetGameInstance(pc)
        setupCombat(pc)
        local time=H.GetGameplayStatics():GetRealTimeSeconds(pc)
        if C.role=='host' then
            local focused,mask=prototype.isFocused()
            local aim=focused and math.floor(mask/16)%2==1
            if hostFov==nil then hostFov=pc.PlayerCameraManager:GetFOVAngle() end
            if aim~=hostAim then pc:FOV(aim and 55 or hostFov);hostAim=aim end
        end
        local own
        if combatView then
            for _,p in ipairs(combatView.players) do if p.id==combatView.you then own=p end end
        end
        local first=C.role=='host' or not thirdPerson
        local dead=own and own.health<=0 or false
        fpWeapon:SetActorHiddenInGame(not first or dead)
        local reloading=own and own.reloadMs>0 or false
        fpWeapon:K2_SetActorRelativeLocation({X=time<recoilUntil and 32 or 38,Y=13,Z=reloading and -26 or -19},false,{},true)
        if dead~=deadInput then
            if dead then pc:SetIgnoreMoveInput(true);pc:SetIgnoreLookInput(true)
            else pc:ResetIgnoreMoveInput();pc:ResetIgnoreLookInput() end
            deadInput=dead
        end
        local message='Connecting combat state...'
        if own then
            local elapsed=math.max(0,time-(combatView.receivedAt or time))*1000
            local phase=dead and (C.scenario=='infiltrator_hunt' and 'ELIMINATED' or ('Respawn '..math.ceil(math.max(0,own.respawnMs-elapsed)/1000)..'s'))
                or reloading and 'Reloading' or 'LMB fire  |  R reload'
            message=string.format('%s  %s\nHealth %d/%d  |  Plasma %d/%d\n%s  |  K %d  D %d',
                combatView.mode:upper(),own.faction:upper(),own.health,own.maxHealth,own.ammo,own.reserve,phase,own.kills,own.deaths)
        end
        local round=_G.TRMPCombat and _G.TRMPCombat.round and _G.TRMPCombat.round()
        if C.scenario=='infiltrator_hunt' and own then
            message=string.format('RESISTANCE NPC | Health %d/%d | Ammo %d\nLMB fire | R reload\nDefend the bunker. Original Infiltrator objectives remain.',own.health,own.maxHealth,own.ammo)
            if dead then message=message..'\nYour soldier is dead. The original mission continues.' end
        end
        if round then
            local status=round.phase=='waiting' and 'Waiting for the other player'
                or round.phase=='finished' and ('Winner: '..round.winner:upper()..' ('..round.reason..')')
                or string.format('Hunt %d:%02d | Resistance NPCs: %d',math.floor(round.seconds/60),round.seconds%60,round.npcs)
            message=message..'\nINFILTRATOR 1v1 | '..status
                ..'\n'..(own and own.faction=='human' and 'Stop the Terminator. Survive 10 minutes to win.' or 'Eliminate the human defender. One life each.')
        end
        if message~=hudValue then
            hudText:SetText(StaticFindObject('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(message));hudValue=message
        end
        for _,body in pairs(bodies) do
            if valid(body.pawn) and valid(body.pawn.PlayerState) then
                local state
                for _,p in ipairs(combatView and combatView.players or {}) do if p.id==body.pawn.PlayerState.PlayerId then state=p end end
                local hidden=body.pawn.bHidden or (state and state.health<=0) or (body.pawn:IsLocallyControlled() and (first or body.cameraHidden))
                body.mesh:SetHiddenInGame(hidden,true)
                if valid(body.weapon) then body.weapon:SetActorHiddenInGame(hidden) end
            end
        end
    end
    local function shotEffect(pc,message)
        local id,sx,sy,sz,ex,ey,ez,result=message:match('^TRMP1|F|(%d+)|([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)|([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)|(%a+)$')
        if not id then return end
        id=tonumber(id)
        local location={X=tonumber(sx),Y=tonumber(sy),Z=tonumber(sz)}
        local finish={X=tonumber(ex),Y=tonumber(ey),Z=tonumber(ez)}
        for _,v in ipairs({location.X,location.Y,location.Z,finish.X,finish.Y,finish.Z}) do if not v or math.abs(v)>1e7 then return end end
        local rotation=StaticFindObject('/Script/Engine.Default__KismetMathLibrary'):FindLookAtRotation(location,finish)
        if combatView and combatView.you==id then
            recoilUntil=H.GetGameplayStatics():GetRealTimeSeconds(pc)+0.09
            if valid(fpWeapon) then location=fpWeapon:K2_GetActorLocation() end
        end
        if effectDefaults then
            if valid(effectDefaults.MuzzleFX) then H.GetGameplayStatics():SpawnEmitterAtLocation(pc,effectDefaults.MuzzleFX,location,rotation,{X=1,Y=1,Z=1},true,0,true) end
            if valid(effectDefaults.ShotSound) then H.GetGameplayStatics():PlaySoundAtLocation(pc,effectDefaults.ShotSound,location,rotation,0.5,1,0,nil,nil,nil) end
        end
    end
    local api={update=safeUpdate,frame=frame,command=command,dispose=dispose,isReady=isReady,
        setCombat=setCombat,combatFrame=combatFrame,shotEffect=shotEffect,
        state=function() return {aiming=aiming,fov=currentFov,thirdPerson=thirdPerson,vision=vision} end}
    _G.TRMPBodies=api
    return api
end
