-- One-life Infiltrator hunt. This module has no engine or file dependencies.
local M={map='/Game/Maps/DLC1/LDLC1_Pasadena3_DLC1_ALL',duration=600}
function M.faction(className,scenario)
    if scenario=='infiltrator_hunt' then
        if className:find('CH_FPPInfiltrator',1,true) then return 'terminator' end
        if className=='Class /Script/Engine.Character' then return 'human' end
        return nil
    end
    return className=='Class /Script/Engine.Character' and 'terminator' or 'human'
end
function M.new()
    return {phase='waiting',winner='none',reason='waiting',seconds=M.duration,npcs=0}
end
function M.step(round,players,now)
    if round.phase=='finished' then return false end
    local human,machine,count=nil,nil,0
    for _,p in pairs(players) do
        count=count+1
        if p.faction=='human' then human=p else machine=p end
    end
    if round.phase=='waiting' then
        if count~=2 or not human or not machine then return false end
        round.phase='active';round.reason='hunt';round.startedAt=now
        round.human=human.id;round.terminator=machine.id
        return true
    end
    local winner,reason
    if not human or not machine then
        winner=human and 'human' or machine and 'terminator' or 'none';reason='disconnected'
    elseif human.health<=0 and machine.health<=0 then winner='none';reason='draw'
    elseif machine.health<=0 then winner='human';reason='eliminated'
    elseif human.health<=0 then winner='terminator';reason='eliminated'
    end
    round.seconds=math.max(0,math.ceil(M.duration-(now-round.startedAt)))
    if not winner and round.seconds==0 then winner='human';reason='survived' end
    if winner then round.phase='finished';round.winner=winner;round.reason=reason;return true end
    return false
end
function M.encode(r)
    return string.format('TRMP1|H|%s|%s|%s|%d|%d',r.phase,r.winner,r.reason,r.seconds,r.npcs)
end
function M.decode(s)
    if type(s)~='string' or #s>160 then return nil end
    local phase,winner,reason,seconds,npcs=s:match('^TRMP1|H|(%a+)|(%a+)|(%a+)|(%d+)|(%d+)$')
    if not phase or not ({waiting=true,active=true,finished=true})[phase]
        or not ({none=true,human=true,terminator=true})[winner]
        or not ({waiting=true,hunt=true,eliminated=true,disconnected=true,draw=true,survived=true})[reason] then return nil end
    seconds,npcs=tonumber(seconds),tonumber(npcs)
    if seconds>M.duration or npcs>4096 then return nil end
    if phase~='finished' and winner~='none' then return nil end
    return {phase=phase,winner=winner,reason=reason,seconds=seconds,npcs=npcs}
end
return M
