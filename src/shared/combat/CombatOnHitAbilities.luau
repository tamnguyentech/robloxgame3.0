--[[
	CombatOnHitAbilities — runs after a damaging hit (CombatEventBus "OnHit" from DamagePipeline.ResolveHit).

	Ability pipeline (where to implement new abilities):

	| Trigger      | When                         | Entry point |
	|--------------|------------------------------|-------------|
	| AutoTimer    | Periodic auto-cast tick      | CombatAutoAbilities.TryApply → EffectResolver.ApplyEffect |
	| OnEntry      | Battle start                 | CombatAutoAbilities.ApplyOnBattleStartPvp / ApplyOnBattleStartNpc → EffectResolver |
	| Passive      | No timer; stat hooks         | CombatFormulas.GetEffectiveAttack (e.g. outrage) — extend that file for similar |
	| OnHit        | Successful hit (finalDamage>0)| This module: onHitEffectHandlers[EffectType] |

	Hybrid (AutoTimer or Passive plus an on-hit rider): keep primary Trigger as-is and set
	OnHitEffectType on the ability row to an effect type registered in onHitEffectHandlers below.

	Data: AbilityDatabase.luau (abilities) + CardDatabase AbilityId.
	Lookup: CardAbilityConfig.GetAbility

	Register at runtime: CombatOnHitAbilities.RegisterOnHitEffectHandler(effectType, fn)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatEventBus = require(script.Parent:WaitForChild("CombatEventBus"))
local CardAbilityConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardAbilityConfig"))
local CombatAbilityState = require(script.Parent:WaitForChild("CombatAbilityState"))

local CombatOnHitAbilities = {}

local onHitEffectHandlers = {}

local function readSecondaryStat(unit, key)
	if not unit or type(unit.statBlock) ~= "table" then
		return 0
	end
	return tonumber(unit.statBlock[key]) or 0
end

function CombatOnHitAbilities.RegisterOnHitEffectHandler(effectType, fn)
	if type(effectType) ~= "string" or effectType == "" or type(fn) ~= "function" then
		return false
	end
	onHitEffectHandlers[effectType] = fn
	return true
end

local function collectOnHitEffectTypes(def)
	if not def then
		return {}
	end
	local types = {}
	if def.Trigger == "OnHit" and type(def.EffectType) == "string" and def.EffectType ~= "" then
		table.insert(types, def.EffectType)
	end
	if type(def.OnHitEffectType) == "string" and def.OnHitEffectType ~= "" then
		table.insert(types, def.OnHitEffectType)
	end
	local seen = {}
	local out = {}
	for _, et in ipairs(types) do
		if not seen[et] then
			seen[et] = true
			table.insert(out, et)
		end
	end
	return out
end

local function applyTransmutationOnHit(attacker, def, _result)
	local frac = tonumber(def and def.Magnitude) or 0.1
	frac = math.clamp(frac, 0, 2)

	local phase = tonumber(CombatAbilityState.getCounter(attacker, "transmutation")) or 0
	if phase == 0 then
		local base = math.max(1, math.floor(tonumber(attacker.baseAttack) or 1))
		attacker.baseAttack = math.max(1, math.floor(base * (1 + frac)))
		CombatAbilityState.setCounter(attacker, "transmutation", 1)
	else
		local maxHp = math.max(1, math.floor(tonumber(attacker.maxHealth) or 1))
		local cur = math.max(0, math.floor(tonumber(attacker.health) or 0))
		local newMax = math.max(1, math.floor(maxHp * (1 + frac)))
		local delta = newMax - maxHp
		attacker.maxHealth = newMax
		attacker.health = math.min(newMax, cur + delta)
		CombatAbilityState.setCounter(attacker, "transmutation", 0)
	end
end

onHitEffectHandlers.TransmutationOnHit = applyTransmutationOnHit

local function applyFireDragonRoarOnHit(attacker, def, result)
	-- Fires once per battle per attacker card state.
	if CombatAbilityState.getFlag(attacker, "firedragonsroar:used") == true then
		return
	end
	if not result then
		return
	end

	local mag = tonumber(def and def.Magnitude) or 0.10
	mag = math.max(0, mag)

	if result.target then
		local target = result.target
		local targetHpAfter = tonumber(target.health) or 0
		local primaryFinal = tonumber(result.finalDamage) or 0
		local hpBefore = math.max(0, targetHpAfter + primaryFinal)

		if hpBefore <= 0 then
			return
		end

		-- Lock immediately so follow-up/other on-hit handlers can't double-trigger.
		CombatAbilityState.setFlag(attacker, "firedragonsroar:used", true)

		local extraRaw = math.max(0, math.floor(hpBefore * mag))
		if extraRaw <= 0 then
			return
		end

		local currentNow = tonumber(result.timestamp) or os.clock()

		-- Apply target mitigation similarly to DamagePipeline (dodge is already resolved on the primary hit).
		local amount = extraRaw
		local reductionPercent = math.clamp(readSecondaryStat(target, "DamageReduction"), 0, 90)
		amount = math.max(0, math.floor(amount * (1 - reductionPercent / 100)))

		-- Anti-magic passive (only relevant if pipeline supports it via cardCategory).
		local atkCat = attacker and attacker.cardCategory
		if atkCat == "Mage" then
			local mageRed = math.clamp(tonumber(target.damageReductionVsMageAttacks) or 0, 0, 0.95)
			if mageRed > 0 then
				amount = math.max(0, math.floor(amount * (1 - mageRed)))
			end
		end

		local incomingBonusUntil = tonumber(target.incomingDamageBonusUntil) or 0
		if incomingBonusUntil > currentNow then
			local incomingBonusFraction = math.clamp(tonumber(target.incomingDamageBonusFraction) or 0, 0, 2)
			if incomingBonusFraction > 0 then
				amount = math.max(0, math.floor(amount * (1 + incomingBonusFraction)))
			end
		end

		local shieldAmount = math.max(0, math.floor(tonumber(target.shieldAmount) or 0))
		local extraAbsorbed = 0
		if shieldAmount > 0 and amount > 0 then
			extraAbsorbed = math.min(shieldAmount, amount)
			target.shieldAmount = shieldAmount - extraAbsorbed
			amount = amount - extraAbsorbed
		end

		if amount > 0 then
			local hp = tonumber(target.health) or 0
			target.health = math.max(0, hp - amount)
		end

		result.rawDamage = (tonumber(result.rawDamage) or 0) + extraRaw
		result.finalDamage = (tonumber(result.finalDamage) or 0) + amount
		result.absorbed = (tonumber(result.absorbed) or 0) + extraAbsorbed
	else
		-- PvE NPC hit: DamagePipeline doesn't have a runtime target, so we need session data.
		local session = result.session
		if not session then
			return
		end
		local npcHpBefore = tonumber(session.npcHealth) or 0
		if npcHpBefore <= 0 then
			return
		end

		CombatAbilityState.setFlag(attacker, "firedragonsroar:used", true)

		local extraRaw = math.max(0, math.floor(npcHpBefore * mag))
		if extraRaw <= 0 then
			return
		end

		result.rawDamage = (tonumber(result.rawDamage) or 0) + extraRaw
		result.finalDamage = (tonumber(result.finalDamage) or 0) + extraRaw
	end
end

onHitEffectHandlers.FireDragonRoarOnHit = applyFireDragonRoarOnHit

local function onHitBusEvent(result)
	if not result or result.isDodged then
		return
	end
	if (tonumber(result.finalDamage) or 0) <= 0 then
		return
	end
	local attacker = result.attacker
	if not attacker then
		return
	end
	if (tonumber(attacker.health) or 0) <= 0 then
		return
	end

	local abilityId = attacker.abilityId
	if type(abilityId) ~= "string" or abilityId == "" then
		return
	end

	local def = CardAbilityConfig.GetAbility(abilityId)
	for _, effectType in ipairs(collectOnHitEffectTypes(def)) do
		local fn = onHitEffectHandlers[effectType]
		if fn then
			fn(attacker, def, result)
		end
	end
end

CombatEventBus.Subscribe("OnHit", 50, onHitBusEvent)

return CombatOnHitAbilities
