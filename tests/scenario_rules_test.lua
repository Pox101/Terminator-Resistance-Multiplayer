return function(S)
    assert(S.faction('BlueprintGeneratedClass /Game/CH_FPPInfiltrator.CH_FPPInfiltrator_C','infiltrator_hunt')=='terminator')
    assert(S.faction('Class /Script/Engine.Character','infiltrator_hunt')=='human')
    assert(S.faction('Class /Script/Engine.Character','arena')=='terminator')
    assert(not S.faction('Class /Game/CH_FPPCharacter','infiltrator_hunt'))
    return 4
end
