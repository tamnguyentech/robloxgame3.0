-- CardAbilityConfig.luau
-- Back-compat facade: ability logic lives in AbilityDatabase.luau. Cards still set AbilityId on the row.

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
