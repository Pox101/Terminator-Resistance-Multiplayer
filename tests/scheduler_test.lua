return function(factory)
    local n,now,updates,frames,deferred,created,removed,frame=0,0,0,0,0,0,0,0
    local events,postMap={},nil
    local world={IsValid=function()return true end,GetAddress=function(self)return self.id end,GetFullName=function()return 'test-world' end,id=1}
    local pc={IsValid=function()return true end,GetWorld=function()return world end}
    local class={IsValid=function()return true end}
    local library={Create=function()
        created=created+1
        return {IsValid=function()return true end,SetVisibility=function()end,AddToViewport=function()end,RemoveFromParent=function()removed=removed+1 end}
    end}
    local original={clock=os.clock,StaticFindObject=StaticFindObject,RegisterCustomEvent=RegisterCustomEvent,
        RegisterLoadMapPostHook=RegisterLoadMapPostHook,ExecuteInGameThread=ExecuteInGameThread}
    os.clock=function()return now end
    StaticFindObject=function(path)return path:find('WidgetBlueprintLibrary',1,true) and library or class end
    RegisterCustomEvent=function(name,callback)events[name]=callback end
    RegisterLoadMapPostHook=function(callback)postMap=callback end
    ExecuteInGameThread=function(callback)deferred=deferred+1;callback() end
    local function check(ok)assert(ok);n=n+1 end
    local ok,err=pcall(function()
        factory({GetKismetSystemLibrary=function()return {GetFrameCount=function()return frame end}end},function(message)assert(not message:find('error',1,true),message)end,function()return pc end,
            function()updates=updates+1;events.Tick()end,function()frames=frames+1 end)
        check(updates==1 and frames==1 and deferred==1 and created==1)
        events.ReceiveTick();check(updates==1 and frames==1)
        now=0.02;frame=1;events.Tick();check(updates==1 and frames==2)
        now=0.11;frame=2;events.Tick();check(updates==2 and frames==3)
        now=0.21;events.ReceiveTick();check(updates==2 and frames==3)
        world.id=2;now=0.22;frame=3;events.Tick();check(created==2 and removed==1)
        now=0.24;frame=4;postMap();check(updates==4 and deferred==1)
        now=1;frame=5;events.Tick();check(updates==5 and deferred==1)
    end)
    os.clock=original.clock
    for _,name in ipairs({'StaticFindObject','RegisterCustomEvent','RegisterLoadMapPostHook','ExecuteInGameThread'}) do _G[name]=original[name] end
    assert(ok,err);return n
end
