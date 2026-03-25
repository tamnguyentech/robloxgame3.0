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
	local result = {
		timestamp = tonumber(now) or os.clock(),
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

	if target then
		local reductionPercent = math.clamp(readSecondaryStat(target, "DamageReduction"), 0, 90)
		amount = math.max(0, math.floor(amount * (1 - reductionPercent / 100)))

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

	result.finalDamage = amount
	return result
end

DamagePipeline.ApplyDamageToBoss = DamagePipeline.ApplyDamageToNpc

return DamagePipeline
