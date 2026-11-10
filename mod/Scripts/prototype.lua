-- Only the base engine proxy is initialized. The game's world-wide BeginPlay
-- flag stays untouched because unrelated game actors are not multiplayer-safe.
return function(H, C, emit)
    local initialized, positioned, placementAfter = {}, {}, {}
    local hostInputReady = {}
    local candidate, readyAfter = 0, 0
    local inputController, processId, pressUntil = nil, nil, {}
    local keyTaps={}
    local lastInputTime, wasFocused = nil, false
    local mouseX, mouseY = {KeyName=FName('MouseX')}, {KeyName=FName('MouseY')}
    local aimState = {focused=false, aiming=false, dt=0}
    local function configureFacing(pawn)
        pawn.bUseControllerRotationYaw = true
        pawn.CharacterMovement.bOrientRotationToMovement = false
    end
    local function valid(o) return o ~= nil and o:IsValid() end
    local function basePawn(p)
        return valid(p) and p:GetClass():GetFullName() == 'Class /Script/Engine.Character'
    end
    local initialize, err
    local sampleInput, inputError = package.loadlib(C.directory .. '/prototype_input.dll', 'sample_input')
    assert(sampleInput, 'Build and copy prototype_input.dll: ' .. tostring(inputError))
    if C.role == 'client' then
        initialize, err = package.loadlib(C.directory .. '/prototype_runtime.dll', 'initialize_local')
        assert(initialize, 'Run Build-Native.cmd and Prepare-Test.ps1: ' .. tostring(err))
    end
    local function keyboardState()
        if not processId then
            local pidFile = assert(io.open(C.directory .. '/process-id.txt', 'r'))
            processId = assert(tonumber(pidFile:read('*a'))); pidFile:close()
        end
        sampleInput()
        local file = assert(io.open(C.directory .. '/input-state.txt', 'r'))
        local pid, mask = file:read('*a'):match('^(%d+)%s+(%d+)'); file:close()
        return tonumber(pid) == processId, tonumber(mask) or 0
    end
    local function update(pc)
        if not valid(pc) or not valid(pc.Pawn) then return end
        local driver = pc:GetWorld().NetDriver
        if not valid(driver) then return end
        if C.role == 'host' then
            local address=pc.Pawn:GetAddress()
            local game=H.GetGameplayStatics():GetGameInstance(pc)
            if not hostInputReady[address] and not game.bIsInLoadingScreen and keyboardState() then
                StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):SetInputMode_GameOnly(pc)
                pc.bShowMouseCursor=false;pc:ResetIgnoreLookInput();pc:ResetIgnoreMoveInput()
                hostInputReady[address]=true
                emit('host_game_input=ready')
            end
            for _, other in ipairs(FindAllOf('PlayerController') or {}) do
                if valid(other) and basePawn(other.Pawn) and not other.Pawn:IsLocallyControlled() then
                    local pawn = other.Pawn
                    configureFacing(pawn)
                    local address = pawn:GetAddress()
                    if not positioned[address] and valid(other.AcknowledgedPawn)
                        and other.AcknowledgedPawn:GetAddress() == address then
                        if not placementAfter[address] then placementAfter[address] = os.time()+5 end
                        if os.time() < placementAfter[address] then return end
                        local origin = pc.Pawn:K2_GetActorLocation()
                        local target = {X=origin.X+200, Y=origin.Y, Z=origin.Z+100}
                        pawn:K2_SetActorLocation(target, false, {}, true)
                        pawn.CharacterMovement.MaxWalkSpeed = C.fullBodies and 320.0 or 300.0
                        other:ClientSetLocation(target, {Pitch=0,Yaw=0,Roll=0})
                        other:ClientSetRotation({Pitch=0,Yaw=0,Roll=0}, true)
                        pawn.CapsuleComponent:SetHiddenInGame(false, true)
                        positioned[address] = true
                        emit('proxy_positioned_near_host=' .. pawn:GetFullName())
                    end
                end
            end
            return
        end
        local pawn = pc.Pawn
        if not valid(driver.ServerConnection) or not basePawn(pawn)
            or not pawn:IsLocallyControlled()
            or pc:GetClass():GetFullName() ~= 'Class /Script/Engine.PlayerController' then return end
        local address = pawn:GetAddress()
        if initialized[address] then return end
        if candidate ~= address then candidate=address; readyAfter=os.time()+2; return end
        if os.time() < readyAfter then return end
        local pidFile = assert(io.open(C.directory .. '/process-id.txt', 'r'))
        local pid = assert(tonumber(pidFile:read('*a'))); pidFile:close()
        processId = pid
        local file = assert(io.open(C.directory .. '/prototype-actors.txt', 'w'))
        file:write(string.format('%d %X %X %X %X', pid, pc:GetAddress(),
            pc:GetClass():GetAddress(), address, pawn:GetClass():GetAddress()))
        file:close()
        initialize()
        pawn.CharacterMovement.MaxWalkSpeed = C.fullBodies and 320.0 or 300.0
        configureFacing(pawn)
        StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):SetInputMode_GameOnly(pc)
        pc.bShowMouseCursor = false
        pc:ResetIgnoreMoveInput()
        pc:ResetIgnoreLookInput()
        initialized[address] = true
        inputController = pc
        emit('selective_local_begin_play_requested=true pawn=' .. pawn:GetFullName())
    end
    if C.role == 'client' then
        for _, name in ipairs({'W','A','S','D'}) do
            RegisterKeyBind(Key[name], function()
                keyTaps[name]=true
            end)
        end
    end
    local function input(pc)
        aimState.focused=false; aimState.aiming=false; aimState.dt=0
        if C.role ~= 'client' or not valid(pc) or not valid(pc.Pawn)
            or not initialized[pc.Pawn:GetAddress()] or not pc.Pawn:IsLocallyControlled() then
            wasFocused=false; lastInputTime=nil; return aimState
        end
        local focused, mask = keyboardState()
        local now = H.GetGameplayStatics():GetRealTimeSeconds(pc)
        local dt=lastInputTime and math.max(0,math.min(now-lastInputTime,0.1)) or 0
        -- Read each engine input sample once, even if the async loop catches up.
        if lastInputTime==now then return aimState end
        lastInputTime=now
        aimState.dt=dt; aimState.focused=focused
        aimState.aiming=focused and math.floor(mask/16)%2==1
        if not focused then wasFocused=false;pressUntil={};keyTaps={};return aimState end
        for name in pairs(keyTaps) do pressUntil[name]=now+0.10 end
        keyTaps={}
        local x=pc:GetInputAnalogKeyState(mouseX)
        local y=pc:GetInputAnalogKeyState(mouseY)
        if wasFocused and (x~=0 or y~=0) then
            local r=pc:GetControlRotation()
            local sensitivity=(C.mouseSensitivity or 0.7)*(aimState.aiming and 0.55 or 1)
            local pitch=(r.Pitch+180)%360-180
            pitch=math.max(-75,math.min(75,pitch+y*sensitivity))
            pc:SetControlRotation({Pitch=pitch,Yaw=(r.Yaw+x*sensitivity+180)%360-180,Roll=0})
        end
        wasFocused=true
        local bits = {W=1,A=2,S=4,D=8}
        local function down(name)
            return math.floor(mask/bits[name])%2 == 1 or (pressUntil[name] or 0) > now
        end
        local forward = (down('W') and 1 or 0) - (down('S') and 1 or 0)
        local right = (down('D') and 1 or 0) - (down('A') and 1 or 0)
        if forward == 0 and right == 0 then return aimState end
        local yaw = math.rad(pc:GetControlRotation().Yaw)
        pc.Pawn:AddMovementInput({X=math.cos(yaw),Y=math.sin(yaw),Z=0}, forward, false)
        pc.Pawn:AddMovementInput({X=-math.sin(yaw),Y=math.cos(yaw),Z=0}, right, false)
        return aimState
    end
    return {update=update, input=input, isFocused=keyboardState,
        clearWorld=function()
            initialized={};positioned={};placementAfter={};hostInputReady={}
            candidate=0;readyAfter=0;inputController=nil;pressUntil={};keyTaps={}
            lastInputTime=nil;wasFocused=false
        end,
        isPlaced=function(pawn) return valid(pawn) and positioned[pawn:GetAddress()]==true end}
end
