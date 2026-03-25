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
	LastAllyHealthShare = {
		Id = "LastAllyHealthShare",
		Name = "Last Ally Health Share",
		Tags = {"Buff", "OnEntry"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnEntry",
		EffectType = "LastAllyHealthShare",
		Magnitude = 0.5,
		DurationSeconds = 0,
		Effects = {
			{
				EffectType = "LastAllyHealthShare",
				Targeting = "AllAllies",
				Magnitude = 0.5,
				Duration = 0,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "When the battle starts, the last ally gains 50% of this card's health.",
	},
	antimagic = {
		Id = "antimagic",
		Name = "Anti-Magic",
		Tags = {"Debuff", "OnEntry", "Passive"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnEntry",
		EffectType = "AntiMagicOnEntry",
		Magnitude = 0,
		DurationSeconds = 10,
		VsMageDamageReductionFraction = 0.5,
		Effects = {
			{
				EffectType = "AntiMagicOnEntry",
				Targeting = "OneEnemy",
				Magnitude = 0,
				Duration = 10,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "On battle start, seal one enemy's abilities for 10 seconds. Passive: take 50% reduced damage from attackers with Category Mage.",
	},
	StunOneEnemyOnEntry = {
		Id = "StunOneEnemyOnEntry",
		Name = "Stun (On Entry)",
		Tags = {"Debuff", "OnEntry"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnEntry",
		EffectType = "StunOneEnemy",
		Magnitude = 0,
		DurationSeconds = 5.0,
		Effects = {
			{
				EffectType = "StunOneEnemy",
				Targeting = "OneEnemy",
				Magnitude = 0,
				Duration = 5.0,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "At battle start, stun 1 enemy for 5 seconds.",
	},
	StunAllEnemiesOnEntry = {
		Id = "StunAllEnemiesOnEntry",
		Name = "Freeze/Sleep (On Entry)",
		Tags = {"Debuff", "OnEntry"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnEntry",
		EffectType = "StunAllEnemies",
		Magnitude = 0,
		DurationSeconds = 5.0,
		Effects = {
			{
				EffectType = "StunAllEnemies",
				Targeting = "AllEnemies",
				Magnitude = 0,
				Duration = 5.0,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "At battle start, stun the enemy party for 5 seconds.",
	},
	DisableDodgeAllEnemiesOnEntry = {
		Id = "DisableDodgeAllEnemiesOnEntry",
		Name = "Webs / Can't Dodge (On Entry)",
		Tags = {"Debuff", "OnEntry"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnEntry",
		EffectType = "DisableDodgeAllEnemies",
		Magnitude = 0,
		DurationSeconds = 6.0,
		Effects = {
			{
				EffectType = "DisableDodgeAllEnemies",
				Targeting = "AllEnemies",
				Magnitude = 0,
				Duration = 6.0,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "At battle start, disable enemy dodges for 6 seconds.",
	},
	-- Death Writer passive:
	-- On battle start, grant this card a 10% proc on every landed attack,
	-- dealing +150% damage (i.e. 2.5x total).
	["noteofdeath"] = {
		Id = "noteofdeath",
		Name = "Note of Death",
		Tags = {"Passive", "Damage", "OnAttack"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnEntry",
		EffectType = "DamageMultiplierOnHitProc",
		Magnitude = 0.10, -- proc chance
		ProcDamageBonus = 1.5, -- +150% damage (bonus), total multiplier = 1 + 1.5 = 2.5
		DurationSeconds = 9999, -- effectively for the whole battle
		Effects = {
			{
				EffectType = "DamageMultiplierOnHitProc",
				Targeting = "Self",
				Magnitude = 0.10,
				ProcDamageBonus = 1.5,
				Duration = 9999,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "Passive: every landed attack has a 10% chance to deal 150% more damage.",
	},
	sunlightyellowoverdrive = {
		Id = "sunlightyellowoverdrive",
		Name = "Sunlight Yellow Overdrive",
		Tags = {"Damage", "OnEntry", "Debuff"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnEntry",
		EffectType = "MultiHitDamageAndHealingReductionOnEntry",
		-- Reused by the generic handler:
		-- - Magnitude = enemy attack fraction (0.5 => 50%)
		-- - DurationSeconds = reduced-healing duration (20s)
		Magnitude = 0.5,
		DurationSeconds = 20,
		-- Extra params consumed by the handler:
		HitCount = 10,
		HealingReductionFraction = 0.25, -- 25% reduced healing
		DefaultCooldownSeconds = 0,
		Description = "On entry: hit an enemy 10 times for 50% of their attack damage; reduce their healing by 25% for 20s.",
	},
	keenjudgement = {
		Id = "keenjudgement",
		Name = "Keen Judgement",
		Tags = {"Debuff"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "AutoTimer",
		EffectType = "EnemyIncomingDamageVulnerability",
		Magnitude = 0.15,
		DurationSeconds = 4,
		Effects = {
			{
				EffectType = "EnemyIncomingDamageVulnerability",
				Targeting = "OneRandomEnemy",
				Magnitude = 0.15,
				Duration = 4,
			},
		},
		DefaultCooldownSeconds = 10,
		Targeting = "OneRandomEnemy",
		Description = "Every 10 seconds, mark one enemy to take 15% more damage for 4 seconds.",
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
