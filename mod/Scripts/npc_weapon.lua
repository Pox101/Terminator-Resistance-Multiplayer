-- Player aiming uses the existing NPC rifle's range, rate, ammo and damage
-- type. Damage still enters the original Infiltrator health system.
return function(H,emit)
    local Collision=require('combat_rules')
    local function valid(o)return o~=nil and o:IsValid()end
    return function(player,target,time)
        if not valid(player.native) or player.native.HealthComponent.Health<=0 then return nil end
        local gun=player.native.WeaponComponent:GetCurrentWeapon(false)
        if not valid(gun) or gun.bIsReloading or time<(player.nextPlayerShot or 0) then return nil end
        if gun.CurrentAmmoInClip<=0 then player.native.WeaponComponent:Reload();return nil end
        local rate=math.max(1,math.min(3000,gun.WeaponConfig.RateOfFire))
        player.nextPlayerShot=time+60/rate
        if not gun.WeaponConfig.bHasInfiniteAmmo then gun.CurrentAmmoInClip=gun.CurrentAmmoInClip-1 end
        local position=player.pawn:K2_GetActorLocation();local r=player.controller:GetControlRotation()
        local pitch,yaw=math.rad(r.Pitch),math.rad(r.Yaw)
        local direction={X=math.cos(pitch)*math.cos(yaw),Y=math.cos(pitch)*math.sin(yaw),Z=math.sin(pitch)}
        local origin={X=position.X,Y=position.Y,Z=position.Z+64}
        local range=math.max(1,math.min(100000,gun.WeaponConfig.WeaponRange))
        local finish={X=origin.X+direction.X*range,Y=origin.Y+direction.Y*range,Z=origin.Z+direction.Z*range}
        local hit={}
        local blocked=H.GetKismetSystemLibrary():LineTraceSingle(player.native,origin,finish,0,false,{},0,hit,true,
            {R=0,G=0,B=0,A=0},{R=0,G=0,B=0,A=0},0)
        local distance=blocked and math.min(range,hit.Distance+2) or range
        local result='miss'
        if target and valid(target.native) and target.native.HealthComponent.Health>0 then
            local capsule=target.native.CapsuleComponent
            local impact=Collision.rayCapsule(origin,direction,target.native:K2_GetActorLocation(),capsule:GetScaledCapsuleRadius(),capsule:GetScaledCapsuleHalfHeight(),distance)
            if impact then
                distance=impact
                local before=target.native.HealthComponent.Health
                H.GetGameplayStatics():ApplyDamage(target.native,gun.WeaponConfig.HitDamage,player.native.Controller,player.native,gun.WeaponConfig.DamageType)
                result='hit';emit('mission_native_damage='..before..'->'..target.native.HealthComponent.Health)
            end
        end
        finish={X=origin.X+direction.X*distance,Y=origin.Y+direction.Y*distance,Z=origin.Z+direction.Z*distance}
        if valid(gun.MuzzleFX) then H.GetGameplayStatics():SpawnEmitterAtLocation(player.native,gun.MuzzleFX,origin,r,{X=1,Y=1,Z=1},true,0,true) end
        if valid(gun.ShotSound) then H.GetGameplayStatics():PlaySoundAtLocation(player.native,gun.ShotSound,origin,r,0.5,1,0,nil,nil,nil) end
        return string.format('TRMP1|F|%d|%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%s',player.id,origin.X,origin.Y,origin.Z,finish.X,finish.Y,finish.Z,result)
    end
end
