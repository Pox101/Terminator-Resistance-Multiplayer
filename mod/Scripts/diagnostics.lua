-- Privacy by projection: arbitrary engine/Lua messages never enter this log.
local M={}
local sites={main=true,scheduler=true,prototype=true,bodies=true,combat=true,
    infiltrator_mission=true,npc_weapon=true,geometry_sync=true,scenario_runtime=true,
    restart_session=true,steam_session=true,versus_menu=true}
local enums={mission_phase={active=true,completed=true,failed=true},
    steam_player_role={host=true,client=true},combat_mode={coop=true,pvp=true}}
local flags={probe_loaded=true,mission_takeover=true,mission_defender_eliminated=true,
    scenario_host=true,first_person_hands=true,versus_menu_opened=true,
    versus_menu_entry_added=true,steam_initial_game_join=true,
    selective_local_begin_play_requested=true,camera_mouse_capture=true}
local generations={session_restart_requested=true,session_restart_waiting=true,
    session_restart_rejoin=true,session_restart_connected=true}
local function mapKind(text)
    if text:find('MAP_StartingMap',1,true) then return 'menu' end
    if text:find('LDLC1_Pasadena3_DLC1_ALL',1,true) then return 'infiltrator' end
    return 'other'
end
function M.project(message)
    if type(message)~='string' or #message>65536 then return end
    local name,value=message:match('^([A-Za-z_]+)=(.*)')
    if not name then
        if flags[message] then return {event=message} end
        if message:find('^probe_loaded;') then name='probe_loaded';value='' else return end
    end
    if flags[name] then return {event=name} end
    if enums[name] and enums[name][value] then return {event=name,value=value} end
    if name=='world' or name=='game_thread_scheduler_ready' then return {event=name,value=mapKind(value)} end
    if generations[name] then local n=tonumber(value);if n and n==math.floor(n) and n>=0 and n<=2147483647 then return {event=name,n=n} end end
    if name=='mission_native_damage' then
        local a,b=value:match('^(%d+%.?%d*)%->(%d+%.?%d*)$');a,b=tonumber(a),tonumber(b)
        if a and b and a<=1000000 and b<=1000000 then return {event=name,before=a,after=b} end
    end
    if name=='scheduler_error' or name=='body_error' then
        local class=value:find('nil value',1,true) and 'nil_access' or value:find('stack',1,true) and 'stack_error'
            or value:find('valid',1,true) and 'invalid_object' or 'other'
        local e={event=name,value=class}
        for file,line in value:gmatch('([A-Za-z_]+)%.lua:(%d+)') do
            if sites[file] and tonumber(line)<=100000 then e.site=file;e.n=tonumber(line);break end
        end
        return e
    end
    if name=='ClientTravelInternal' or name=='OpenLevel' then return {event='travel_requested'} end
    if name=='HandleNetworkError' or name=='HandleTravelError' then return {event=name} end
    if name=='steam_party_ended' then
        local known={owner_left=true,peer_disconnected=true,transport_failed=true,incompatible=true}
        if known[value] then return {event=name,value=value} end
    end
end
local function json(t)
    local out={};for k,v in pairs(t) do
        -- All strings originate in the constants/projection above or UUID/time.
        out[#out+1]='"'..k..'":'..(type(v)=='number' and tostring(v) or '"'..v..'"')
    end
    return '{'..table.concat(out,',')..'}'
end
function M.new(C)
    local session
    local f=io.open(C.directory..'/diagnostic-session-id.txt','r')
    if f then session=f:read(37);f:close() end
    if not session or not session:match('^[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+%-[a-f0-9]+$') or #session~=36 then
        return {record=function()end,pulse=function()end}
    end
    local seq,nextPulse,windowAt,windowCount,dropped=0,0,os.time(),0,0
    local path=C.directory..'/diagnostic-events.jsonl'
    local function append(e)
        local file=io.open(path,'a');if not file then return end
        local size=file:seek('end') or 0
        if size>=262144 then
            file:close();os.remove(path..'.1');os.rename(path,path..'.1');file=io.open(path,'w');if not file then return end
        end
        seq=seq+1;e.seq=seq;e.session=session;e.utc=os.date('!%Y-%m-%dT%H:%M:%SZ')
        file:write(json(e)..'\n');file:close()
    end
    local function record(message)
        local e=M.project(message);if not e then return end
        local now=os.time()
        if now~=windowAt then
            if dropped>0 then append({event='events_suppressed',n=dropped});dropped=0 end
            windowAt=now;windowCount=0
        end
        windowCount=windowCount+1
        if windowCount>20 then dropped=math.min(1000000,dropped+1);return end
        append(e)
    end
    local function pulse()
        local now=os.time();if now<nextPulse then return end;nextPulse=now+2
        local file=io.open(C.directory..'/diagnostic-heartbeat.json','w');if not file then return end
        file:write(json({session=session,utc=os.date('!%Y-%m-%dT%H:%M:%SZ'),seq=seq}));file:close()
    end
    return {record=record,pulse=pulse}
end
return M
