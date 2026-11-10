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
    check(M.phase('active',1000,1,false)=='active','living Terminator with active native quest continues')
    check(M.phase('active',nil,nil,false)=='active','missing state never invents a result')
    check(M.phase('active',0,1,false)=='failed','native Terminator death ends mission')
    check(M.phase('active',1000,1,true)=='failed','native failure without health loss is respected')
    check(M.phase('active',1000,3,false)=='failed','native quest failure ends mission')
    check(M.phase('active',1000,2,false)=='completed','only native quest completion succeeds')
    check(M.phase('active',1000,1,false,true)=='completed','native Infiltrator summary ends its still-active quest')
    check(M.phase('active',0,1,true,true)=='failed','failure summary never counts as mission completed')
    check(M.phase('failed',1000,1,false)=='failed','healing cannot restart an ended session')
    check(M.phase('completed',0,3,true)=='completed','completed native outcome is stable')
    decoded=M.decode(M.encode(2,rows,'completed'))
    check(decoded and decoded.missionPhase=='completed' and decoded.players[2].health==0,'completed mission and dead defender are independent')
    check(M.decode(M.encode(2,rows,'failed')).missionPhase=='failed','native failure reaches client')
    check(M.decode('TRMP1|M|2|2,human,0,200,45').missionPhase=='active','older local updates remain readable')
    check(not M.decode('TRMP1|M|2|victory|2,human,200,200,45'),'invented result rejected')
    check(not M.decode('TRMP1|M|2|active|2,human,200,200,45;'),'trailing empty slot rejected')
    check(not M.decode('TRMP1|M|2|active|2,human,200,200,45;;1,terminator,1000,1000,0'),'empty slot rejected')
    rows[2].reloading=true;decoded=M.decode(M.encode(2,rows))
    check(decoded.players[2].reloadMs>0,'native reload drives client hand animation')
    rows[2].reloading=false;decoded=M.decode(M.encode(2,rows))
    check(decoded.players[2].reloadMs==0,'native reload completion restores idle hands')
    check(not M.decode('TRMP1|M|2|active|2,human,200,200,45,2'),'invalid native reload flag rejected')
    check(M.outcome('completed','terminator')=='success','native completion is Terminator victory')
    check(M.outcome('completed','human')=='fail','native completion is Resistance defeat')
    check(M.outcome('failed','terminator')=='fail','native failure is Terminator defeat')
    check(M.outcome('failed','human')=='success','native failure is Resistance victory')
    check(M.outcome('active','human')==nil and M.outcome('active','terminator')==nil,'active mission has no winner')
    check(M.outcome('completed','unknown')==nil,'invalid faction never claims victory')
    return n
end
