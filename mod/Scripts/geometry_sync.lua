-- The original mission moves dungeon prefabs randomly. Their transforms are
-- not replicated by the shipped game, so a client must mirror the host's two
-- existing interior placements without changing any mission objectives.
return function(H,C,emit)
    local allowed={['/Game/Maps/DLC1/Prefabs/Dungeon_01']=true,['/Game/Maps/DLC1/Prefabs/Dungeon_02_scientist']=true}
    local states,nextSend,localControllerAddress,worldAddress={},0,0,0
    local function valid(o)return o~=nil and o:IsValid()end
    local function decode(text)
        if #text>512 then return nil end
        local name,payload=text:match('^TRMP1|G|([^|]+)|([^|]+)$')
        if not allowed[name] then return nil end
        local values={}
        for value in payload:gmatch('[^,]+') do
            local n=tonumber(value);if not n or n~=n or math.abs(n)>1e7 then return nil end
            values[#values+1]=n
        end
        if #values~=7 then return nil end
        local length=0;for i=4,7 do length=length+values[i]^2 end
        if math.abs(length-1)>0.001 then return nil end
        return name,values
    end
    if C.role=='client' then
        RegisterHook('/Script/Engine.PlayerController:ClientMessage',function(context,message,kind)
            if kind:get():ToString()~='TRMPG' or context:get():GetAddress()~=localControllerAddress then return end
            local text=message:get():ToString();local name,values=decode(text)
            if name and (not states[name] or states[name].key~=text) then states[name]={key=text,values=values,phase='pending'} end
        end)
    end
    local function update(pc)
        localControllerAddress=valid(pc) and pc:GetAddress() or 0
        if not valid(pc) or not valid(pc.Pawn) or not valid(pc:GetWorld().NetDriver)
            or not pc:GetWorld():GetFullName():find('LDLC1_Pasadena3_DLC1_ALL',1,true) then return end
        if worldAddress~=pc:GetWorld():GetAddress() then
            worldAddress=pc:GetWorld():GetAddress();nextSend=0
            for _,state in pairs(states) do state.phase='pending' end
        end
        if C.role=='host' then
            local time=H.GetGameplayStatics():GetRealTimeSeconds(pc)
            if time<nextSend then return end;nextSend=time+2
            pc:GetWorld().StreamingLevels:ForEach(function(_,wrapped)
                local level=wrapped:get();local name=level:GetWorldAssetPackageFName():ToString()
                if allowed[name] and level:IsLevelVisible() then
                    local t=level.LevelTransform;local p,q=t.Translation,t.Rotation
                    local text=string.format('TRMP1|G|%s|%.3f,%.3f,%.3f,%.6f,%.6f,%.6f,%.6f',name,p.X,p.Y,p.Z,q.X,q.Y,q.Z,q.W)
                    for _,controller in ipairs(FindAllOf('PlayerController') or {}) do
                        if valid(controller) and valid(controller.Pawn) and not controller:IsLocalController() then controller:ClientMessage(text,FName('TRMPG'),0) end
                    end
                end
            end)
        else
            for name,state in pairs(states) do
                if state.phase~='done' then
                    local level=H.GetGameplayStatics():GetStreamingLevel(pc,FName(name))
                    if valid(level) then
                        if state.phase=='pending' then
                            level.bDisableDistanceStreaming=true;level:SetShouldBeVisible(false);level:SetShouldBeLoaded(false)
                            state.phase='unloading'
                        elseif state.phase=='unloading' and not level:IsLevelLoaded() then
                            local v=state.values
                            level.LevelTransform.Translation={X=v[1],Y=v[2],Z=v[3]}
                            level.LevelTransform.Rotation={X=v[4],Y=v[5],Z=v[6],W=v[7]}
                            level.LevelTransform.Scale3D={X=1,Y=1,Z=1}
                            level:SetShouldBeLoaded(true);level:SetShouldBeVisible(true);state.phase='loading'
                        elseif state.phase=='loading' and level:IsLevelVisible() then
                            state.phase='done';emit('mission_interior_synced='..name)
                        end
                    end
                end
            end
        end
    end
    return {update=update,decode=decode}
end
