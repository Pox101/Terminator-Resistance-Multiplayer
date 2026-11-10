return function(factory)
    local n,blocked,reloads,damageCalls=0,false,0,0
    local function check(value)assert(value);n=n+1 end
    local absent={IsValid=function()return false end}
    local gun={IsValid=function()return true end,CurrentAmmoInClip=3,bIsReloading=false,
        WeaponConfig={RateOfFire=250,WeaponRange=500,HitDamage=50,DamageType='native-type',bHasInfiniteAmmo=false},
        MuzzleFX=absent,ShotSound=absent}
    local native={IsValid=function()return true end,HealthComponent={Health=400},Controller='native-ai',
        WeaponComponent={GetCurrentWeapon=function()return gun end,Reload=function()reloads=reloads+1 end}}
    local target={native={IsValid=function()return true end,HealthComponent={Health=1000},
        K2_GetActorLocation=function()return {X=150,Y=0,Z=0} end,
        CapsuleComponent={GetScaledCapsuleRadius=function()return 34 end,GetScaledCapsuleHalfHeight=function()return 88 end}}}
    local player={id=2,native=native,pawn={K2_GetActorLocation=function()return {X=0,Y=0,Z=0} end},
        controller={GetControlRotation=function()return {Pitch=0,Yaw=0} end}}
    local gs={ApplyDamage=function(_,actor,amount,instigator,source,kind)
        assert(instigator=='native-ai' and source==native and kind=='native-type' and amount==50)
        damageCalls=damageCalls+1;actor.HealthComponent.Health=actor.HealthComponent.Health-amount
    end}
    local H={GetGameplayStatics=function()return gs end,GetKismetSystemLibrary=function()return {
        LineTraceSingle=function(_,context,origin,finish,channel,complex,ignored,draw,hit)
            assert(context==native);hit.Distance=40;return blocked
        end} end}
    local shoot=factory(H,function()end)
    check(shoot(player,target,0):match('|hit$')~=nil and target.native.HealthComponent.Health==950)
    check(gun.CurrentAmmoInClip==2 and damageCalls==1)
    check(shoot(player,target,0.1)==nil and gun.CurrentAmmoInClip==2)
    blocked=true
    check(shoot(player,target,0.25):match('|miss$')~=nil and damageCalls==1)
    gun.CurrentAmmoInClip=0
    check(shoot(player,target,0.5)==nil and reloads==1)
    gun.CurrentAmmoInClip=3;gun.bIsReloading=true
    check(shoot(player,target,1)==nil and damageCalls==1)
    gun.bIsReloading=false;gun.WeaponConfig.bHasInfiniteAmmo=true;blocked=false
    check(shoot(player,target,2)~=nil and gun.CurrentAmmoInClip==3)
    native.HealthComponent.Health=0
    check(shoot(player,target,3)==nil and damageCalls==2)
    return n
end
