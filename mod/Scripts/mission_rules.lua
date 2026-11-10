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
function M.encode(you,players)
    local rows={}
    for _,p in ipairs(players) do rows[#rows+1]=string.format('%d,%s,%d,%d,%d',p.id,p.faction,p.health,p.maxHealth,p.ammo) end
    return 'TRMP1|M|'..you..'|'..table.concat(rows,';')
end
function M.decode(text)
    if type(text)~='string' or #text>1024 then return nil end
    local you,payload=text:match('^TRMP1|M|(%d+)|(.+)$');you=tonumber(you)
    if not you or you>2147483647 then return nil end
    local players,seen={},{}
    for row in payload:gmatch('[^;]+') do
        local id,faction,hp,max,ammo=row:match('^(%d+),(%a+),(%d+),(%d+),(%d+)$')
        id,hp,max,ammo=tonumber(id),tonumber(hp),tonumber(max),tonumber(ammo)
        if not id or id>2147483647 or seen[id] or (faction~='human' and faction~='terminator')
            or max<1 or max>10000 or hp>max or ammo>10000 then return nil end
        seen[id]=true;players[#players+1]={id=id,faction=faction,health=hp,maxHealth=max,ammo=ammo,reserve=0,reloadMs=0,respawnMs=0,kills=0,deaths=hp==0 and 1 or 0}
        if #players>2 then return nil end
    end
    if not seen[you] then return nil end
    return {mode='pvp',you=you,players=players}
end
return M
