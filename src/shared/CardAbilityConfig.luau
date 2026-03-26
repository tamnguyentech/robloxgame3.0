-- CardAbilityConfig.luau
-- Back-compat facade: definitions in AbilityDatabase.luau. Cards set AbilityId on the row.
-- Runtime: AutoTimer → CombatAutoAbilities; OnEntry → ApplyOnBattleStart*; OnHit → CombatOnHitAbilities;
-- Passive stat hooks → CombatFormulas (see AbilityDatabase file header).

local AbilityDatabase = require(script.Parent:WaitForChild("AbilityDatabase"))

local CardAbilityConfig = {}

CardAbilityConfig.Abilities = AbilityDatabase.Abilities

function CardAbilityConfig.GetAbility(abilityId)
	return AbilityDatabase.GetAbility(abilityId)
end

function CardAbilityConfig.RegisterAbility(abilityId, def)
	return AbilityDatabase.RegisterAbility(abilityId, def)
end

return CardAbilityConfig
