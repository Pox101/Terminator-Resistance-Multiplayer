-- Appearance defaults. Mission objectives are owned by the original game.
local M={map='/Game/Maps/DLC1/LDLC1_Pasadena3_DLC1_ALL'}
function M.faction(className,scenario)
    if scenario=='infiltrator_hunt' then
        if className:find('CH_FPPInfiltrator',1,true) then return 'terminator' end
        if className=='Class /Script/Engine.Character' then return 'human' end
        return nil
    end
    return className=='Class /Script/Engine.Character' and 'terminator' or 'human'
end
return M
