-- Local session generations survive map reloads. Only a previously attached
-- peer can follow a restart; a fresh client must still explicitly join once.
local M={}
local phases={menu=true,starting=true,ready=true,restarting=true,loading=true}
function M.decode(text)
    if type(text)~='string' or #text>160 then return nil end
    local run,epoch,phase,stamp=text:match('^TRMP_SESSION1|(%d+:%d+)|(%d+)|(%a+)|(%d+)%s*$')
    if not run or #run>32 or not phases[phase] then return nil end
    epoch,stamp=tonumber(epoch),tonumber(stamp)
    if not epoch or epoch>2147483647 or not stamp or stamp>9999999999 then return nil end
    return {run=run,epoch=epoch,phase=phase,stamp=stamp}
end
function M.encode(s)
    assert(phases[s.phase] and s.run:match('^%d+:%d+$'))
    assert(s.epoch>=0 and s.epoch<=2147483647 and s.epoch%1==0)
    return string.format('TRMP_SESSION1|%s|%d|%s|%d\n',s.run,s.epoch,s.phase,s.stamp)
end
function M.decision(attached,s,now,pending)
    if not attached or not s or attached.run~=s.run then return 'none' end
    if s.stamp>now+10 or now-s.stamp>300 then return 'none' end
    if pending and s.phase=='menu' then return 'leave' end
    if pending and s.phase=='ready' and s.epoch==attached.epoch then return 'cancel' end
    if s.epoch<=attached.epoch then return 'none' end
    if s.phase=='ready' then return 'join' end
    if s.phase=='restarting' or s.phase=='loading' or s.phase=='starting' then return 'wait' end
    return 'none'
end
return M
