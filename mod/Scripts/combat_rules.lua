-- Engine-independent authority rules. Clients never supply damage, ammo or hits.
local M={capacity=30,reserve=120,damage=25,interval=0.20,reloadSeconds=2.0,respawnSeconds=5,range=20000,maxPlayers=8}
function M.newPlayer(id,faction)
    assert(type(id)=='number' and id%1==0 and id>=0)
    assert(faction=='human' or faction=='terminator')
    local max=faction=='terminator' and 1000 or 100
    return {id=id,faction=faction,health=max,maxHealth=max,ammo=M.capacity,reserve=M.reserve,
        nextShot=0,reloadAt=0,respawnAt=0,kills=0,deaths=0,shots=0,revision=0}
end
function M.advance(p,now)
    if p.respawnAt>0 and now>=p.respawnAt then
        p.health=p.maxHealth;p.ammo=M.capacity;p.reserve=M.reserve
        p.reloadAt=0;p.respawnAt=0;p.nextShot=now+0.5;p.revision=p.revision+1
        return 'respawn'
    end
    if p.reloadAt>0 and now>=p.reloadAt then
        local n=math.min(M.capacity-p.ammo,p.reserve)
        p.ammo=p.ammo+n;p.reserve=p.reserve-n;p.reloadAt=0;p.revision=p.revision+1
        return 'reloaded'
    end
end
function M.request(p,action,now)
    if type(now)~='number' or now~=now or math.abs(now)==math.huge then return false,'clock' end
    if p.health<=0 then return false,'dead' end
    if action=='reload' then
        if p.reloadAt>0 then return false,'reloading' end
        if p.ammo>=M.capacity then return false,'full' end
        if p.reserve<=0 then return false,'no_reserve' end
        p.reloadAt=now+M.reloadSeconds;p.revision=p.revision+1;return true,'reload'
    end
    if action~='fire' then return false,'unknown' end
    if p.reloadAt>0 then return false,'reloading' end
    if now+0.00001<p.nextShot then return false,'rate' end
    if p.ammo<=0 then return false,'empty' end
    p.ammo=p.ammo-1;p.nextShot=now+M.interval;p.shots=p.shots+1;p.revision=p.revision+1
    return true,'fire'
end
function M.damagePlayer(shooter,target,mode,now)
    if shooter==target or shooter.health<=0 or target.health<=0 then return false,'inactive' end
    if mode~='pvp' or shooter.faction==target.faction then return false,'friendly' end
    return M.hurt(target,M.damage,now,shooter)
end
function M.hurt(target,amount,now,shooter)
    if type(amount)~='number' or amount~=amount or amount<=0 or amount>10000 then return false,'damage' end
    if target.health<=0 then return false,'inactive' end
    target.health=math.max(0,target.health-math.ceil(amount));target.revision=target.revision+1
    if target.health==0 then
        target.respawnAt=target.allowRespawn==false and 0 or now+M.respawnSeconds
        target.reloadAt=0;target.deaths=target.deaths+1
        if shooter then shooter.kills=shooter.kills+1;shooter.revision=shooter.revision+1 end
        return true,'death'
    end
    return true,'hit'
end
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<1e8 end
-- Exact ray/vertical-capsule intersection, including the two hemispheres.
function M.rayCapsule(origin,dir,center,radius,halfHeight,limit)
    for _,v in ipairs({origin.X,origin.Y,origin.Z,dir.X,dir.Y,dir.Z,center.X,center.Y,center.Z,radius,halfHeight,limit}) do
        if not finite(v) then return nil end
    end
    if radius<=0 or halfHeight<radius or limit<=0 then return nil end
    local length=dir.X*dir.X+dir.Y*dir.Y+dir.Z*dir.Z
    if math.abs(length-1)>0.001 then return nil end
    local ox,oy=origin.X-center.X,origin.Y-center.Y
    local segment=halfHeight-radius
    local best
    local function keep(t) if t and t>=0 and t<=limit and (not best or t<best) then best=t end end
    local a=dir.X*dir.X+dir.Y*dir.Y
    if a>1e-8 then
        local b=ox*dir.X+oy*dir.Y
        local c=ox*ox+oy*oy-radius*radius
        local disc=b*b-a*c
        if disc>=0 then
            for _,t in ipairs({(-b-math.sqrt(disc))/a,(-b+math.sqrt(disc))/a}) do
                if math.abs(origin.Z+dir.Z*t-center.Z)<=segment then keep(t) end
            end
        end
    end
    for _,z in ipairs({center.Z-segment,center.Z+segment}) do
        local oz=origin.Z-z
        local b=ox*dir.X+oy*dir.Y+oz*dir.Z
        local c=ox*ox+oy*oy+oz*oz-radius*radius
        local disc=b*b-c
        if disc>=0 then keep(-b-math.sqrt(disc));keep(-b+math.sqrt(disc)) end
    end
    return best
end
function M.encode(mode,you,players,now)
    local rows={}
    for _,p in ipairs(players) do
        rows[#rows+1]=string.format('%d,%s,%d,%d,%d,%d,%d,%d,%d,%d',p.id,p.faction,p.health,p.maxHealth,p.ammo,p.reserve,
            math.max(0,math.ceil((p.reloadAt-now)*1000)),math.max(0,math.ceil((p.respawnAt-now)*1000)),p.kills,p.deaths)
    end
    return 'TRMP1|S|'..mode..'|'..you..'|'..table.concat(rows,';')
end
function M.decode(message)
    if type(message)~='string' or #message>2048 then return nil end
    local mode,you,payload=message:match('^TRMP1|S|(%a+)|(%d+)|(.+)$')
    if mode~='coop' and mode~='pvp' then return nil end
    you=tonumber(you);if not you or you>2147483647 then return nil end
    local players,ids={},{}
    for row in payload:gmatch('[^;]+') do
        local id,faction,hp,max,ammo,reserve,reload,respawn,kills,deaths=row:match('^(%d+),(%a+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)$')
        if not id or (faction~='human' and faction~='terminator') then return nil end
        id,hp,max,ammo,reserve,reload,respawn,kills,deaths=tonumber(id),tonumber(hp),tonumber(max),tonumber(ammo),tonumber(reserve),tonumber(reload),tonumber(respawn),tonumber(kills),tonumber(deaths)
        if ids[id] or id>2147483647 or max<1 or max>10000 or hp>max or ammo>M.capacity or reserve>M.reserve
            or reload>M.reloadSeconds*1000 or respawn>M.respawnSeconds*1000 or kills>1e7 or deaths>1e7 then return nil end
        ids[id]=true;players[#players+1]={id=id,faction=faction,health=hp,maxHealth=max,ammo=ammo,reserve=reserve,
            reloadMs=reload,respawnMs=respawn,kills=kills,deaths=deaths}
        if #players>M.maxPlayers then return nil end
    end
    if not ids[you] then return nil end
    return {mode=mode,you=you,players=players}
end
return M
