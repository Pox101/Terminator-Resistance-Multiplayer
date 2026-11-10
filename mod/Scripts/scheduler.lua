-- No recurring async Lua callbacks: one fixed game-thread event drains work.
-- WB_Empty's native Blueprint Tick only records widget geometry.
return function(H,emit,context,update,input,resetWorld,dormant)
    local busy,lastFrame,nextUpdate=false,-1,0
    local travelling=false
    local system=H.GetKismetSystemLibrary()
    local widget,worldAddress=nil,0
    local function valid(o)return o~=nil and o:IsValid()end
    local function ensureTick(pc)
        if not valid(pc) or not valid(pc:GetWorld()) then return end
        local address=pc:GetWorld():GetAddress()
        if valid(widget) and worldAddress==address then return end
        if valid(widget) then widget:RemoveFromParent() end
        local path='/Game/UI/Globals/WB_Empty.WB_Empty'
        local class=StaticFindObject(path..'_C')
        if not valid(class) then LoadAsset(path);class=StaticFindObject(path..'_C') end
        if not valid(class) then return end
        widget=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(pc,class,pc)
        widget:SetVisibility(3);widget:AddToViewport(-100)
        worldAddress=address;emit('game_thread_scheduler_ready='..pc:GetWorld():GetFullName())
    end
    local function pump()
        if busy or travelling then return end
        -- Many widgets/actors tick in one engine frame. Wall-clock gating
        -- re-runs expensive work for each widget when a frame is slow.
        local frame=system:GetFrameCount()
        if frame==lastFrame then return end
        local now=os.clock()
        busy=true;lastFrame=frame
        local ok,err=pcall(function()
            if now>=nextUpdate then
                nextUpdate=now+0.1
                if not dormant or not dormant() then ensureTick(context()) end
                update()
            end
            if not travelling then input() end
        end)
        if not ok then emit('scheduler_error='..tostring(err)) end
        busy=false
    end
    RegisterCustomEvent('Tick',pump)
    RegisterCustomEvent('ReceiveTick',pump)
    local function beforeTravel()
        -- World-owned widgets and component handles may already be tearing
        -- down. Drop Lua references without calling methods on old objects.
        travelling=true;widget=nil;worldAddress=0;lastFrame=-1;nextUpdate=0
        if resetWorld then resetWorld() end
    end
    -- UE4SS 3.0.1's LoadMap pre-callback corrupts its Lua call stack in this
    -- build. Supported OpenLevel/ClientTravel hooks call beforeTravel instead.
    RegisterLoadMapPostHook(function()beforeTravel();travelling=false;pump()end)
    -- The only deferred callback is created at mod load; no asynchronous loop
    -- creates registry references while game-thread work is being executed.
    ExecuteInGameThread(pump)
    return {beforeTravel=beforeTravel}
end
