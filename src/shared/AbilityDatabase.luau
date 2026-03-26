-- AbilityDatabase.luau
-- Canonical ability definitions (separate from CardDatabase). Cards reference abilities by Id via CardData.AbilityId.
--
-- Merge order for combat is unchanged: CardDatabase row + defaults; cooldown can fall back to DefaultCooldownSeconds here.
--
-- Where triggers run (implement new behavior in these modules):
--   AutoTimer  → CombatAutoAbilities.TryApply → EffectResolver.ApplyEffect (timer tick)
--   OnEntry    → CombatAutoAbilities.ApplyOnBattleStartPvp / ApplyOnBattleStartNpc → EffectResolver
--   Passive    → CombatFormulas / other stat readers (no cast), e.g. low-HP damage in GetEffectiveAttack
--   OnHit      → CombatOnHitAbilities (after successful hit; EffectType must have a handler there)
--   Attached strike (e.g. fang follow-up) → CombatFangFollowup + PvpBattleService / NpcBattleService / EffectResolver multihit
-- Hybrid: use AutoTimer or Passive as Trigger and set OnHitEffectType to also run an on-hit handler
--   registered in CombatOnHitAbilities (same string family as EffectType for timer effects).
--
-- Record shape (extend as you add systems):
--   Id                         string   (same as table key; must match CardData.AbilityId)
--   Name                       string?  display name
--   Description                string?
--   Trigger                    string?  AutoTimer | OnEntry | Passive | OnHit
--   OnHitEffectType            string?  optional; when set, CombatOnHitAbilities runs this even if Trigger is not OnHit
--   Targeting                  string?  passed to target resolver / legacy tags
--   EffectType                 string   branch key for EffectResolver (timer/entry) or CombatOnHitAbilities (OnHit)
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

	hamonmentor = {
		Id = "hamonmentor",
		Name = "Hamon Mentor",
		Tags = { "Buff", "OnEntry", "Team" },
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnEntry",
		EffectType = "HamonMentorOnEntry",
		Magnitude = 0.10,
		DurationSeconds = 9999,
		Effects = {
			{
				EffectType = "HamonMentorOnEntry",
				Targeting = "AllAllies",
				Magnitude = 0.10,
				Duration = 9999,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "On entry, buff all allies: +10% Max HP (and matching heal) and +10% attack for the battle.",
	},
	cowardscourage = {
		Id = "cowardscourage",
		Name = "Coward's Courage",
		Tags = { "Buff", "OnEntry" },
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnEntry",
		EffectType = "CowardScourageOnEntry",
		Magnitude = 0.05,
		DurationSeconds = 0,
		Effects = {
			{
				EffectType = "CowardScourageOnEntry",
				Targeting = "Self",
				Magnitude = 0.05,
				Duration = 0,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "When the battle starts, this card gains 5% of the strongest ally's Attack and Max HP (strongest by Attack + Max HP).",
	},
	killerinstincts = {
		Id = "killerinstincts",
		Name = "Killer Instincts",
		Tags = { "Buff", "Dodge", "Speed", "OnEntry" },
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnEntry",
		EffectType = "KillerInstinctsOnEntry",
		Magnitude = 0.1,
		DurationSeconds = 9999,
		Effects = {
			{
				EffectType = "KillerInstinctsOnEntry",
				Targeting = "Self",
				Magnitude = 0.1,
				Duration = 9999,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "On entry, gain +10% Dodge chance, +10% attack speed, and the next eligible incoming attack is guaranteed dodged once.",
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
	evilcontainmentwave = {
		Id = "evilcontainmentwave",
		Name = "Evil Containment Wave",
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
	rock = {
		Id = "rock",
		Name = "Jajanken: Rock",
		Tags = { "Passive", "Damage", "OnAttack" },
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnEntry",
		EffectType = "DamageMultiplierOnHitProc",
		Magnitude = 0.33,
		ProcDamageBonus = 1,
		DurationSeconds = 9999,
		Effects = {
			{
				EffectType = "DamageMultiplierOnHitProc",
				Targeting = "Self",
				Magnitude = 0.33,
				ProcDamageBonus = 1,
				Duration = 9999,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "Each landed attack has a 33% chance to deal double damage.",
	},
	fangoverfang = {
		Id = "fangoverfang",
		Name = "Fang over Fang",
		Tags = { "Passive", "Damage", "OnAttack" },
		Conditions = {},
		HandlerModule = nil,
		Trigger = "Passive",
		EffectType = "FangFollowupAttack",
		Magnitude = 0.2,
		DurationSeconds = 0,
		DefaultCooldownSeconds = 0,
		Description = "After each connecting strike, deal a follow-up hit for 20% of this card's effective attack (no extra chain).",
	},
	starburstscream = {
		Id = "starburstscream",
		Name = "Starburst Scream",
		Tags = { "Passive", "Damage", "OnAttack" },
		Conditions = {},
		HandlerModule = nil,
		Trigger = "Passive",
		EffectType = "StarburstScreamAttack",
		-- Counter burst:
		-- After every 2 connecting primary hits, unleash 3 follow-up hits.
		Magnitude = 0.5,
		DurationSeconds = 0,
		DefaultCooldownSeconds = 0,
		Description = "After every 2 connecting primary hits, unleash 3 follow-up hits that deal 50% of this card's effective attack.",
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
	outrage = { 
		Id = "outrage",
		Name = "Outrage",
		Tags = {"Passive", "Damage"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "Passive",
		EffectType = "SelfDamageWhenLowHp",
		Magnitude = 0.2,
		HpRatioThreshold = 0.5,
		DurationSeconds = 0,
		Effects = {
			{
				EffectType = "SelfDamageWhenLowHp",
				Targeting = "Self",
				Magnitude = 0.2,
				HpRatioThreshold = 0.5,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "While below 50% max HP, this card deals 20% more damage.",
	},	
	transmutation = {
		Id = "transmutation",
		Name = "Transmutation",
		Tags = { "OnHit", "Buff" },
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnHit",
		EffectType = "TransmutationOnHit",
		Magnitude = 0.1,
		DurationSeconds = 0,
		Effects = {
			{
				EffectType = "TransmutationOnHit",
				Targeting = "Self",
				Magnitude = 0.1,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "After each successful hit, alternates +10% base attack or +10% max HP (and heals by the same amount).",
	},
	errornull = {
		Id = "errornull",
		Name = "Error Null",
		Tags = {"Passive", "Damage"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "Passive",
		EffectType = "MissingHpDamageBoost",
		Magnitude = 1,
		DurationSeconds = 0,
		Effects = {
			{
				EffectType = "MissingHpDamageBoost",
				Targeting = "Self",
				Magnitude = 1,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "This card gains damage equal to missing health.",
	},
	firedragonsroar = {
		Id = "firedragonsroar",
		Name = "Fire Dragonsroar",
		Tags = {"OnHit", "Damage"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnHit",
		EffectType = "FireDragonRoarOnHit",
		Magnitude = 0.10,
		DurationSeconds = 0,
		DefaultCooldownSeconds = 0,
		Effects = {
			{
				EffectType = "FireDragonRoarOnHit",
				Targeting = "Target",
				Magnitude = 0.10,
			},
		},
		Description = "On the first successful hit, deal extra damage equal to 10% of the enemy's current HP.",
	},
	selfdestruct = {
		Id = "selfdestruct",
		Name = "Self Destruct",
		Tags = {"OnDeath", "Damage"},
		Conditions = {},
		HandlerModule = nil,
		Trigger = "OnDeath",
		EffectType = "SelfDestructOnDeath",
		Magnitude = 1,
		DurationSeconds = 0,
		Effects = {
			{
				EffectType = "SelfDestructOnDeath",
				Targeting = "Enemy",
				Magnitude = 1,
			},
		},
		DefaultCooldownSeconds = 0,
		Description = "On death, deal 100% of this card's max HP as damage to the enemy that killed it.",
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
