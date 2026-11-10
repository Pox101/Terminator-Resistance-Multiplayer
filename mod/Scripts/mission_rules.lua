-- Select an existing bunker soldier; mission objectives and native deaths stay
-- owned by the game. Eliminating a defender never completes the mission.
local M={}
function M.select(candidates,bunker)
    if not bunker then return nil end
    local best,distance=nil,5000*5000
    for _,npc in ipairs(candidates) do
        if npc.health>0 and not npc.assigned and npc.infantry and not npc.commander then
            local p=npc.position;local d=(p.X-bunker.X)^2+(p.Y-bunker.Y)^2+(p.Z-bunker.Z)^2
            if d<distance then best=npc;distance=d end
        end
    end
    return best
end
local phases={active=true,completed=true,failed=true}
-- The wire phase describes the original Infiltrator mission. The defender
-- has the opposite objective, including when other NPCs stop the Infiltrator.
function M.outcome(phase,faction)
    if (phase~='completed' and phase~='failed') or (faction~='human' and faction~='terminator') then return nil end
    return ((phase=='completed')==(faction=='terminator')) and 'success' or 'fail'
end
-- Only native mission state ends the session. A dead defender is deliberately
-- absent from this decision: the Infiltrator still has its original objectives.
function M.phase(previous,terminatorHealth,objectiveState,nativeFailure,nativeSummary)
    if previous=='completed' or previous=='failed' then return previous end
    if nativeFailure or objectiveState==3 or (type(terminatorHealth)=='number' and terminatorHealth<=0) then return 'failed' end
    -- The shipped Infiltrator ending opens its summary while the quest actor
    -- still reports Active/stage 2. Observe that native callback as well.
    if objectiveState==2 or nativeSummary then return 'completed' end
    return 'active'
end
function M.encode(you,players,phase)
    assert(phases[phase or 'active'],'Invalid mission phase')
    local rows={}
    for _,p in ipairs(players) do rows[#rows+1]=string.format('%d,%s,%d,%d,%d,%d',p.id,p.faction,p.health,p.maxHealth,p.ammo,p.reloading and 1 or 0) end
    return 'TRMP1|M|'..you..'|'..(phase or 'active')..'|'..table.concat(rows,';')
end
function M.decode(text)
    if type(text)~='string' or #text>1024 then return nil end
    local you,phase,payload=text:match('^TRMP1|M|(%d+)|(%a+)|(.+)$')
    -- Earlier local previews sent no phase field.
    if not you then you,payload=text:match('^TRMP1|M|(%d+)|(.+)$');phase='active' end
    you=tonumber(you)
    if not phases[phase] then return nil end
    if not you or you>2147483647 then return nil end
    local players,seen={},{}
    if payload:sub(1,1)==';' or payload:sub(-1)==';' or payload:find(';;',1,true) then return nil end
    for row in payload:gmatch('[^;]+') do
        local id,faction,hp,max,ammo,reloading=row:match('^(%d+),(%a+),(%d+),(%d+),(%d+),([01])$')
        if not id then id,faction,hp,max,ammo=row:match('^(%d+),(%a+),(%d+),(%d+),(%d+)$');reloading='0' end
        id,hp,max,ammo=tonumber(id),tonumber(hp),tonumber(max),tonumber(ammo)
        if not id or id>2147483647 or seen[id] or (faction~='human' and faction~='terminator')
            or max<1 or max>10000 or hp>max or ammo>10000 then return nil end
        seen[id]=true;players[#players+1]={id=id,faction=faction,health=hp,maxHealth=max,ammo=ammo,reserve=0,reloadMs=reloading=='1' and 1 or 0,respawnMs=0,kills=0,deaths=hp==0 and 1 or 0}
        if #players>2 then return nil end
    end
    if not seen[you] then return nil end
    return {mode='pvp',you=you,players=players,missionPhase=phase}
end
return M
