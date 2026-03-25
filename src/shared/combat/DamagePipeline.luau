-- DamagePipeline.luau
-- Centralized HP / PvE NPC HP changes and hit resolution.

local DamagePipeline = {}
local CombatEventBus = require(script.Parent:WaitForChild("CombatEventBus"))

local function readSecondaryStat(unit, key)
	if not unit or type(unit.statBlock) ~= "table" then
		return 0
	end
	return tonumber(unit.statBlock[key]) or 0
end

function DamagePipeline.ApplyDamageToUnit(target, rawAmount)
	if not target then
		return 0
	end
	local amount = math.max(0, math.floor(tonumber(rawAmount) or 0))
	local hp = tonumber(target.health) or 0
	target.health = math.max(0, hp - amount)
	return amount
end

function DamagePipeline.ApplyHealToUnit(target, rawAmount)
	if not target then
		return 0
	end
	local amount = math.max(0, math.floor(tonumber(rawAmount) or 0))
	local maxHp = math.max(1, math.floor(tonumber(target.maxHealth) or 1))

	-- Reduced-healing debuff (e.g., "enemy healing -25% for N seconds").
	-- Stored as a fraction (0..1) on the unit state.
	local currentNow = os.clock()
	local redFrac = tonumber(target.healingReductionFraction) or 0
	local redUntil = tonumber(target.healingReductionUntil) or 0
	if redUntil > currentNow and redFrac > 0 then
		amount = math.max(0, math.floor(amount * (1 - math.clamp(redFrac, 0, 1))))
	end

	local hp = tonumber(target.health) or 0
	target.health = math.min(maxHp, hp + amount)
	return amount
end

function DamagePipeline.ApplyDamageToNpc(session, rawAmount)
	if not session then
		return 0
	end
	local amount = math.max(0, math.floor(tonumber(rawAmount) or 0))
	local nh = tonumber(session.npcHealth) or 0
	session.npcHealth = math.max(0, nh - amount)
	return amount
end

function DamagePipeline.ResolveHit(attacker, target, rawDamage, now)
	local amount = math.max(0, math.floor(tonumber(rawDamage) or 0))
	local currentNow = tonumber(now) or os.clock()
	local result = {
		timestamp = currentNow,
		rawDamage = amount,
		finalDamage = amount,
		absorbed = 0,
		isCrit = false,
		isDodged = false,
		attacker = attacker,
		target = target,
	}

	if amount <= 0 then
		result.finalDamage = 0
		return result
	end

	-- Accuracy reduces dodge chance directly.
	if target then
		local dodge = readSecondaryStat(target, "Dodge")
		local accuracy = readSecondaryStat(attacker, "Accuracy")
		-- Control effects: prevent dodges while stunned or while dodge is disabled (e.g. webs).
		local stunUntil = tonumber(target.stunUntil) or 0
		local dodgeDisabledUntil = tonumber(target.dodgeDisabledUntil) or 0
		if stunUntil > currentNow or dodgeDisabledUntil > currentNow then
			dodge = 0
		end
		local effectiveDodge = math.clamp(dodge - accuracy, 0, 95)
		if math.random() <= (effectiveDodge / 100) then
			result.isDodged = true
			result.finalDamage = 0
			return result
		end
	end

	-- Crit uses CritChance/CritDamage from attacker's stat block.
	local critChance = math.clamp(readSecondaryStat(attacker, "CritChance"), 0, 100)
	if critChance > 0 and math.random() <= (critChance / 100) then
		local critDamage = math.max(0, readSecondaryStat(attacker, "CritDamage"))
		local critMultiplier = 1 + (critDamage / 100)
		amount = math.max(1, math.floor(amount * critMultiplier))
		result.isCrit = true
	end

	-- Generic on-hit damage procs:
	-- Evaluated after crit, before target damage reduction/shields.
	local procs = attacker and attacker.onHitDamageProcs
	if type(procs) == "table" then
		local totalMultiplier = 1
		for i = #procs, 1, -1 do
			local p = procs[i]
			local untilT = tonumber(p and p.untilTime) or 0
			if untilT <= currentNow then
				table.remove(procs, i)
			else
				local chance = math.clamp(tonumber(p and p.chance) or 0, 0, 1)
				if chance > 0 and math.random() <= chance then
					local bonus = math.max(0, tonumber(p and p.bonus) or 0) -- bonus amount
					totalMultiplier *= (1 + bonus)
					result.onHitDamageProc = true
				end
			end
		end

		if totalMultiplier > 1 then
			amount = math.max(1, math.floor(amount * totalMultiplier))
		end
	end

	if target then
		local reductionPercent = math.clamp(readSecondaryStat(target, "DamageReduction"), 0, 90)
		amount = math.max(0, math.floor(amount * (1 - reductionPercent / 100)))
		local incomingBonusUntil = tonumber(target.incomingDamageBonusUntil) or 0
		if incomingBonusUntil > currentNow then
			local incomingBonusFraction = math.clamp(tonumber(target.incomingDamageBonusFraction) or 0, 0, 2)
			if incomingBonusFraction > 0 then
				amount = math.max(0, math.floor(amount * (1 + incomingBonusFraction)))
			end
		end

		local shieldAmount = math.max(0, math.floor(tonumber(target.shieldAmount) or 0))
		if shieldAmount > 0 and amount > 0 then
			local absorbed = math.min(shieldAmount, amount)
			target.shieldAmount = shieldAmount - absorbed
			amount = amount - absorbed
			result.absorbed = absorbed
		end

		result.finalDamage = amount
		if amount > 0 then
			DamagePipeline.ApplyDamageToUnit(target, amount)
			CombatEventBus.Fire("OnHit", result)
		end
		return result
	end

	-- PvE (and any pooled target): no RuntimeCardState target — damage applied by caller (e.g. ApplyDamageToNpc).
	result.finalDamage = amount
	if amount > 0 then
		CombatEventBus.Fire("OnHit", result)
	end
	return result
end

DamagePipeline.ApplyDamageToBoss = DamagePipeline.ApplyDamageToNpc

return DamagePipeline
