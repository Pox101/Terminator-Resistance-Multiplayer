return function(D)
 local n=0;local function check(ok,label)assert(ok,label);n=n+1 end
 check(D.project('account=secret')==nil,'unknown event excluded')
 check(D.project('versus_menu_opened').event=='versus_menu_opened','flag without payload')
 check(D.project('world=World C:/Users/Private/LDLC1_Pasadena3_DLC1_ALL').value=='infiltrator','world name projected')
 check(D.project('mission_phase=failed').value=='failed','known phase')
 check(D.project('mission_phase=secret')==nil,'unknown phase excluded')
 check(D.project('mission_native_damage=62.5->0.0').after==0,'numeric native damage')
 check(D.project('mission_native_damage=1e99->0')==nil,'unbounded values excluded')
 check(D.project('session_restart_rejoin=2').n==2,'restart generation')
 check(D.project('session_restart_rejoin=-2')==nil,'bad generation')
 local e=D.project('scheduler_error=C:/Users/Private/mod/Scripts/bodies.lua:123: attempt to index a nil value SECRET ghp_credentials')
 check(e.value=='nil_access' and e.site=='bodies' and e.n==123,'source/line projected without arbitrary error text')
 for _,v in pairs(e) do check(not tostring(v):find('SECRET',1,true) and not tostring(v):find('Private',1,true),'no free text') end
 check(D.project('ClientTravelInternal=secret.ip.example:7777').event=='travel_requested','travel address excluded')
 check(D.project('mission_takeover=Actor /private/account/path').event=='mission_takeover','actor identity excluded')
 check(D.project(string.rep('x',65537))==nil,'oversized event')
 check(D.project('steam_party_ended=owner_left').value=='owner_left','disconnect reason enum')
 check(D.project('steam_party_ended=private-data')==nil,'unknown disconnect reason')
 return n
end
