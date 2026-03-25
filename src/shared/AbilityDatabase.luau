-- AbilityDatabase.luau
-- Canonical ability definitions (separate from CardDatabase). Cards reference abilities by Id via CardData.AbilityId.
--
-- Merge order for combat is unchanged: CardDatabase row + defaults; cooldown can fall back to DefaultCooldownSeconds here.
--
-- Record shape (extend as you add systems):
--   Id                         string   (same as table key; must match CardData.AbilityId)
--   Name                       string?  display name
--   Description                string?
--   Trigger                    string?  "AutoTimer" (current auto-battle), later: OnHit, OnDeath, ...
--   Targeting                  string?  passed to target resolver / legacy tags
--   EffectType                 string   engine branch in CombatAutoAbilities / future EffectResolver
--   Magnitude                  number?
--   DurationSeconds            number?
--   DefaultCooldownSeconds     number   fallback when CardData.AbilityCooldownSeconds omitted
--   Effects                    table?   future: ordered list of { Kind, ... } data-driven steps
--   Tags                       table?   future: { "Buff", "AoE", ... }
--   HandlerModule              string?  future: optional scripted handler under Shared/combat/Handlers
--
-- Add new abilities below; keep Ids stable once cards reference them.

local AbilityDatabase = {}

AbilityDatabase.Abilities = {
	IceAge = {
		Id = "IceAge",
		Name = "Ice Age",
		Tags = {"Buff", "Speed"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "AutoTimer",
		EffectType = "TeamAttackSpeedBoost",
		Magnitude = 0.4,
		DurationSeconds = 6.0,
		Effects = {
			{
				EffectType = "TeamAttackSpeedBoost",
				Targeting = "AllAllies",
				Magnitude = 0.4,
				Duration = 6.0,
			},
		},
		DefaultCooldownSeconds = 20,
		Targeting = "AllAllies",
		Description = "Team attack speed boost.",
	},
	AttackSpeedBoost = {
		Id = "AttackSpeedBoost",
		Name = "Attack Speed Boost",
		Tags = {"Buff", "Speed"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "AutoTimer",
		EffectType = "TeamAttackSpeedBoost",
		Magnitude = 0.35,
		DurationSeconds = 5.0,
		Effects = {
			{
				EffectType = "TeamAttackSpeedBoost",
				Targeting = "AllAllies",
				Magnitude = 0.35,
				Duration = 5.0,
			},
		},
		DefaultCooldownSeconds = 12,
		Targeting = "AllAllies",
		Description = "Raises ally attack speed temporarily.",
	},
	AttackDamageBoost = {
		Id = "AttackDamageBoost",
		Name = "Attack Damage Boost",
		Tags = {"Buff", "Damage"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "AutoTimer",
		EffectType = "TeamAttackDamageBoost",
		Magnitude = 0.5,
		DurationSeconds = 5.0,
		Effects = {
			{
				EffectType = "TeamAttackDamageBoost",
				Targeting = "AllAllies",
				Magnitude = 0.5,
				Duration = 5.0,
			},
		},
		DefaultCooldownSeconds = 15,
		Targeting = "AllAllies",
		Description = "Raises ally damage temporarily.",
	},
	HealAlly = {
		Id = "HealAlly",
		Name = "Heal Ally",
		Tags = {"Heal"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "AutoTimer",
		EffectType = "HealLowestAlly",
		Magnitude = 0.3,
		DurationSeconds = 0,
		Effects = {
			{
				EffectType = "HealLowestAlly",
				Targeting = "LowestHealthAlly",
				Magnitude = 0.3,
				Duration = 0,
			},
		},
		DefaultCooldownSeconds = 9,
		Targeting = "LowestHealthAlly",
		Description = "Heals the lowest-HP ally.",
	},
	-- Mr Satan — on entry debuff enemy party outgoing attack (PvP: cards; PvE: boss).
	WorldChampionsBluff = {
		Id = "WorldChampionsBluff",
		Name = "World Champion's Bluff",
		Tags = {"Debuff", "OnEntry"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnEntry",
		EffectType = "EnemyPartyAttackDown",
		Magnitude = 0.10,
		DurationSeconds = 10,
		Effects = {
			{
				EffectType = "EnemyPartyAttackDown",
				Targeting = "AllEnemies",
				Magnitude = 0.10,
				Duration = 10,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "On entry, reduce enemy party attack by 10% for 10 seconds.",
	},
}

function AbilityDatabase.GetAbility(abilityId)
	if type(abilityId) ~= "string" or abilityId == "" then
		return nil
	end
	return AbilityDatabase.Abilities[abilityId]
end

-- Optional: register at runtime (tools / tests). Prefer editing this file for shipped content.
function AbilityDatabase.RegisterAbility(abilityId, def)
	if type(abilityId) ~= "string" or abilityId == "" or type(def) ~= "table" then
		return false
	end
	AbilityDatabase.Abilities[abilityId] = def
	return true
end

return AbilityDatabase
