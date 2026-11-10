-- Localhost feasibility probe. All save access uses isolated test profiles.
local H = require('UEHelpers')
local C = require('config')
if C.scenario=='infiltrator_hunt' then
    local diagnostics=assert(package.loadlib(C.directory..'/prototype_runtime.dll','log_exceptions'));diagnostics()
end
if C.nativeHudGuard then
    local guard, err = package.loadlib(C.directory .. '/controller_guard.dll', 'install_guard')
    assert(guard, 'Build and copy controller_guard.dll before launching: ' .. tostring(err))
    guard()
end
local movingUntil = 0
local driverConfigured = false
local prototypeModeAddress = 0
local function valid(o) return o ~= nil and o:IsValid() end
local function safe(f)
    local ok, value = pcall(f)
    if ok then return tostring(value) end
    return 'unavailable'
end
local function emit(message)
    local line = os.date('!%Y-%m-%dT%H:%M:%SZ') .. ' [' .. C.role .. '] ' .. message
    print('[TRMP] ' .. line .. '\n')
    local f = io.open(C.directory .. '/probe.log', 'a')
    if f then f:write(line .. '\n'); f:close() end
end
local function context()
    local gs = H.GetGameplayStatics()
    local engine = FindFirstOf('GameEngine')
    if not valid(engine) or not valid(engine.GameViewport) then return nil end
    return gs:GetPlayerController(engine.GameViewport, 0)
end
local prototype = C.prototypePawn and require('prototype')(H, C, emit) or nil
local bodies = prototype and C.fullBodies and require('bodies')(H,C,emit,prototype) or nil
local combat = bodies and C.combatEnabled and require('combat')(H,C,emit,prototype,bodies) or nil
local scenario=C.scenario=='infiltrator_hunt' and require('scenario_runtime')(H,C,emit) or nil
local geometry=C.scenario=='infiltrator_hunt' and require('geometry_sync')(H,C,emit) or nil
local listenReadyAfter,listenWorld=0,0
local function configureScenarioHosting()
    if C.role~='host' or C.scenario~='infiltrator_hunt' then return end
    local pc=context()
    if not valid(pc) or not valid(pc.Pawn) then return end
    local world=pc:GetWorld()
    if not world:GetFullName():find('LDLC1_Pasadena3_DLC1_ALL',1,true) or valid(world.NetDriver) then return end
    local game=H.GetGameplayStatics():GetGameInstance(pc)
    if listenWorld~=world:GetAddress() or game.bIsInLoadingScreen or game.bIsInCutscene then
        listenWorld=world:GetAddress();listenReadyAfter=os.time()+12;return
    end
    if os.time()<listenReadyAfter then return end
    listenReadyAfter=os.time()+30
    local pf=assert(io.open(C.directory..'/process-id.txt','r'));local pid=assert(tonumber(pf:read('*a')));pf:close()
    local f=assert(io.open(C.directory..'/listen-world.txt','w'))
    f:write(string.format('%d %X %X',pid,world:GetAddress(),world:GetClass():GetAddress()));f:close()
    if scenario then scenario.prepare(pc) end
    local listen=assert(package.loadlib(C.directory..'/prototype_runtime.dll','listen_local'));listen()
    emit('scenario_host=in_place listener='..safe(function() return world.NetDriver:GetFullName() end))
end
local function configureLocalNetworking()
    if driverConfigured then return end
    local engine = FindFirstOf('GameEngine')
    if not valid(engine) then return end
    local class = StaticFindObject('/Script/OnlineSubsystemUtils.IpNetDriver')
    local defaults = StaticFindObject('/Script/OnlineSubsystemUtils.Default__IpNetDriver')
    defaults.InitialConnectTimeout=300
    defaults.ConnectionTimeout=300
    emit('ip_class=' .. safe(function() return class:GetFullName() end)
        .. ' connection_class=' .. safe(function() return defaults.NetConnectionClassName:ToString() end))
    engine.NetDriverDefinitions:ForEach(function(_, wrapped)
        local definition = wrapped:get()
        emit('driver_definition=' .. definition.DefName:ToString() .. ' before=' .. definition.DriverClassName:ToString())
        if definition.DefName:ToString() == 'GameNetDriver' then
            definition.DriverClassName = FName('OnlineSubsystemUtils.IpNetDriver')
            definition.DriverClassNameFallback = FName('OnlineSubsystemUtils.IpNetDriver')
            driverConfigured = true
            emit('network_config=GameNetDriver uses IpNetDriver for localhost testing')
            emit('driver_readback=' .. definition.DriverClassName:ToString())
        end
    end)
end
local function configurePrototypePlayers()
    if not C.prototypePawn then return end
    local pc=context()
    if not valid(pc) or not valid(pc.Pawn) then return end
    local gm=H.GetGameplayStatics():GetGameMode(pc)
    if not valid(gm) or gm:GetAddress()==prototypeModeAddress then return end
    gm.PlayerControllerClass=StaticFindObject('/Script/Engine.PlayerController')
    gm.DefaultPawnClass=StaticFindObject('/Script/Engine.Character')
    if C.scenario=='infiltrator_hunt' and valid(gm.GameSession) then gm.GameSession.MaxPlayers=2 end
    prototypeModeAddress=gm:GetAddress()
    emit('prototype_players=base PlayerController and Character for subsequent joins')
end
local function snapshot()
    local pc = context()
    if not valid(pc) then emit('waiting_for_local_controller'); return end
    local gs = H.GetGameplayStatics()
    local world = pc:GetWorld()
    emit('world=' .. world:GetFullName())
    emit('local_controller=' .. pc:GetFullName()
        .. ' game_mode=' .. safe(function() return gs:GetGameMode(pc):GetFullName() end))
    local driver = world.NetDriver
    emit('net_driver=' .. safe(function() return driver:GetFullName() end)
        .. ' clients=' .. safe(function() return valid(driver) and C.role=='host' and driver.ClientConnections:GetArrayNum() or 0 end)
        .. ' server_connection=' .. safe(function() return driver.ServerConnection:GetFullName() end))
    for _, p in ipairs(FindAllOf('PlayerController') or {}) do
        if valid(p) then
            emit('controller=' .. p:GetFullName() .. ' pawn=' .. safe(function() return p.Pawn:GetFullName() end)
                .. ' state=' .. safe(function() return p.PlayerState:GetFullName() end))
        end
    end
    for _, p in ipairs(FindAllOf('Pawn') or {}) do
        if valid(p) and p:IsPlayerControlled() then
            emit('player_pawn=' .. p:GetFullName() .. ' role=' .. safe(function() return p:GetLocalRole() end)
                .. ' local=' .. safe(function() return p:IsLocallyControlled() end)
                .. ' replicates=' .. safe(function() return p.bReplicates end)
                .. ' position=' .. safe(function()
                    local v = p:K2_GetActorLocation()
                    return string.format('%.1f,%.1f,%.1f', v.X, v.Y, v.Z)
                end))
            emit('player_facing=' .. p:GetFullName() .. ' rotation=' .. safe(function()
                local r=p:K2_GetActorRotation()
                return string.format('%.1f,%.1f,%.1f',r.Pitch,r.Yaw,r.Roll)
            end))
        end
    end
end
local function command(cmd)
    local pc = context()
    if not valid(pc) then emit('command_rejected=no_local_controller ' .. cmd); return end
    local gs = H.GetGameplayStatics()
    if cmd == 'experiment' then
        local chunk = assert(loadfile(C.directory .. '/experiment.lua'))
        chunk()(H, C, emit, pc)
    elseif cmd == 'host' or cmd == 'host-menu' then
        if C.scenario=='infiltrator_hunt' then
            emit('host_automatic=original_mission_is_hosted_in_place_after_intro');return
        end
        local level = pc:GetWorld():GetFullName():match('World ([^%.]+)%.')
        assert(level, 'Could not resolve current map')
        if cmd ~= 'host-menu' and (level:lower():find('menu') or level:find('MAP_StartingMap')) then emit('host_rejected=load_gameplay_level_first'); return end
        emit('host_requested=' .. level)
        gs:OpenLevel(pc, FName(level), true, 'listen?port=7777')
    elseif cmd == 'join' then
        emit('join_requested=127.0.0.1:7777')
        H.GetKismetSystemLibrary():ExecuteConsoleCommand(pc, 'open 127.0.0.1:7777', pc)
    elseif cmd:sub(1,4) == 'map ' then
        local level = cmd:sub(5)
        assert(level:match('^/Game/[%w_/]+$'), 'Invalid map path')
        emit('map_requested=' .. level)
        gs:OpenLevel(pc, FName(level), true, '')
    elseif cmd == 'move' then
        movingUntil = os.time() + 3
        emit('local_movement_requested=3_seconds')
    elseif cmd == 'status' then
        snapshot()
    elseif combat and combat.command(pc,cmd) then
        return
    elseif (cmd=='view' or cmd=='vision') and bodies then
        bodies.command(pc,cmd)
    elseif cmd == 'quit' then
        H.GetKismetSystemLibrary():ExecuteConsoleCommand(pc, 'quit', pc)
    else emit('unknown_command=' .. cmd) end
end
local ticks = 0
local keyCommands={}
local function update()
    configureLocalNetworking()
    configurePrototypePlayers()
    configureScenarioHosting()
    if scenario then scenario.update(context()) end
    if geometry then geometry.update(context()) end
    if prototype then prototype.update(context()) end
    if bodies then bodies.update(context()) end
    if combat then combat.update(context()) end
    local f=io.open(C.directory..'/command.txt','r')
    if f and valid(context()) then
        local cmd=f:read('*a'):match('^%s*(.-)%s*$');f:close()
        os.remove(C.directory..'/command.txt')
        if cmd~='' then command(cmd) end
    elseif f then f:close() end
    local queued=keyCommands;keyCommands={}
    if not prototype or prototype.isFocused() then
        for _,cmd in ipairs(queued) do command(cmd) end
    end
    ticks=ticks+1
    if ticks%50==0 then snapshot() end
end
local function input()
    local pc=context()
    local aim=prototype and prototype.input(pc) or nil
    if bodies and bodies.frame then bodies.frame(pc,aim) end
    if combat then combat.input(pc,aim);bodies.combatFrame(pc) end
    if movingUntil>os.time() and valid(pc) and valid(pc.Pawn) and pc.Pawn:IsLocallyControlled() then
        pc.Pawn:AddMovementInput({X=1,Y=0,Z=0},1.0,false)
    end
end
-- Fixed game-thread callbacks avoid creating/unreferencing Lua registry
-- entries concurrently in LoopAsync + ExecuteInGameThread (UE4SS issue 1180).
require('scheduler')(H,emit,context,update,input)
local function key(cmd)
    if #keyCommands<16 then keyCommands[#keyCommands+1]=cmd end
end
RegisterKeyBind(Key.F6, function() key('host') end)
RegisterKeyBind(Key.F7, function() key('join') end)
RegisterKeyBind(Key.F8, function() key('status') end)
RegisterKeyBind(Key.F9, function() key('move') end)
emit('probe_loaded; F6=host F7=join F8=status F9=move')
for _, event in ipairs({'HandleNetworkError','HandleTravelError'}) do
    local ok, err = pcall(function()
        RegisterHook('/Script/Engine.GameInstance:' .. event, function(_, failure)
            emit(event .. '=' .. tostring(failure:get()))
        end)
    end)
    if not ok then emit('error_hook_unavailable=' .. event .. ' ' .. tostring(err)) end
end
NotifyOnNewObject('/Script/Engine.NetDriver', function(obj)
    emit('driver_created=' .. obj:GetFullName())
end)
RegisterHook('/Script/Engine.GameplayStatics:OpenLevel', function(_, _, level, absolute, options)
    emit('OpenLevel level=' .. level:get():ToString() .. ' options=' .. options:get():ToString())
end)
RegisterHook('/Script/Engine.PlayerController:ClientTravelInternal', function(_, url)
    emit('ClientTravelInternal url=' .. url:get():ToString())
end)
