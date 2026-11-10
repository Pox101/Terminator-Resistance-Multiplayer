return function(M)
    local n=0;local function check(v,s)n=n+1;assert(v,s)end
    local b={X=100,Y=0,Z=0}
    local ordinary={health=200,infantry=true,commander=false,position={X=200,Y=0,Z=0}}
    local commander={health=400,infantry=true,commander=true,position=b}
    local far={health=200,infantry=true,position={X=10000,Y=0,Z=0}}
    check(M.select({ordinary,commander,far},b)==ordinary,'select bunker guard, preserve commander')
    check(not M.select({commander,far},b),'never replace a distant patrol or commander')
    check(not M.select({ordinary},nil),'no invented bunker if native selection missing')
    ordinary.assigned=true;check(not M.select({ordinary},b),'already controlled slot excluded');ordinary.assigned=false
    ordinary.health=0;check(not M.select({ordinary},b),'dead native slot excluded');ordinary.health=200
    local rows={{id=1,faction='terminator',health=1000,maxHealth=1000,ammo=0},{id=2,faction='human',health=200,maxHealth=200,ammo=45}}
    local decoded=M.decode(M.encode(2,rows))
    check(decoded and decoded.players[2].ammo==45 and decoded.players[2].maxHealth==200,'native ammo and health survive replication')
    rows[2].health=0;decoded=M.decode(M.encode(2,rows))
    check(decoded and decoded.players[2].health==0 and not decoded.winner,'defender death never declares mission won')
    check(not M.decode('TRMP1|M|2|2,human,201,200,45'),'health overflow rejected')
    check(not M.decode('TRMP1|M|2|1,human,200,200,45'),'missing owner rejected')
    check(not M.decode('TRMP1|M|2|2,human,200,200,45;2,human,200,200,45'),'duplicate slots rejected')
    check(not M.decode(string.rep('a',1025)),'oversized mission update rejected')
    return n
end
