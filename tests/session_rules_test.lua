return function(M)
    local n=0;local function check(v,label)assert(v,label);n=n+1 end
    local s={run='1234:1800000000',epoch=4,phase='ready',stamp=1800000001}
    local a={run=s.run,epoch=3}
    local decoded=M.decode(M.encode(s))
    check(decoded and decoded.epoch==4 and decoded.run==s.run,'session generation survives roundtrip')
    check(M.decision(a,s,s.stamp,false)=='join','attached client follows a new ready world')
    check(M.decision(nil,s,s.stamp,false)=='none','fresh client never joins automatically')
    check(M.decision({run='9999:1800000000',epoch=3},s,s.stamp,false)=='none','another host process is not the old session')
    check(M.decision({run=s.run,epoch=4},s,s.stamp,false)=='none','same generation never causes duplicate travel')
    s.phase='restarting';check(M.decision(a,s,s.stamp,false)=='wait','pause old-world reads before native restart')
    s.phase='loading';check(M.decision(a,s,s.stamp,false)=='wait','wait for native world initialization')
    s.phase='starting';check(M.decision(a,s,s.stamp,false)=='wait','wait until the new listener exists')
    s.phase='menu';check(M.decision(a,s,s.stamp,false)=='none','leaving to the menu never starts a match')
    check(M.decision(a,s,s.stamp,true)=='leave','leaving during restart cancels the pending join')
    s.phase='ready';s.epoch=3;check(M.decision(a,s,s.stamp,true)=='cancel','cancel a refused native restart without joining the same world')
    s.epoch=4;check(M.decision(a,s,s.stamp+301,true)=='none','stale state never starts travel')
    check(M.decision(a,s,s.stamp-11,true)=='none','future-dated state rejected')
    check(not M.decode('TRMP_SESSION1|1234:1800000000|4|unknown|1800000001'),'unknown phase rejected')
    check(not M.decode('TRMP_SESSION1|1234:1800000000|2147483648|ready|1800000001'),'generation overflow rejected')
    check(not M.decode('TRMP_SESSION1|1234:1800000000|4|ready|nan'),'invalid timestamp rejected')
    check(not M.decode(string.rep('x',161)),'bounded session file')
    return n
end
