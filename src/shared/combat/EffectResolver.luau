local CombatFormulas = require(script.Parent:WaitForChild("CombatFormulas"))
local DamagePipeline = require(script.Parent:WaitForChild("DamagePipeline"))

local EffectResolver = {}
local handlers = {}

function EffectResolver.RegisterEffectHandler(effectType, fn)
	if type(effectType) ~= "string" or effectType == "" or type(fn) ~= "function" then
		return false
	end
	handlers[effectType] = fn
	return true
end

function EffectResolver.ApplyEffect(effectType, context)
	local handler = handlers[effectType]
	if not handler then
		return nil
	end
	return handler(context or {})
end

EffectResolver.RegisterEffectHandler("TeamAttackSpeedBoost", function(context)
	local allies = CombatFormulas.FilterAlive(context.allies or {})
	local now = tonumber(context.now) or os.clock()
	local magnitude = math.max(0, tonumber(context.magnitude) or 0)
	local durationSeconds = math.max(0, tonumber(context.durationSeconds) or 0)
	local targetSlotIndices = {}
	for _, ally in ipairs(allies) do
		ally.speedBoostMagnitude = math.max(tonumber(ally.speedBoostMagnitude) or 0, magnitude)
		ally.speedBoostUntil = math.max(tonumber(ally.speedBoostUntil) or 0, now + durationSeconds)
		table.insert(targetSlotIndices, ally.slotIndex)
	end
	return {
		targetSlotIndices = targetSlotIndices,
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		applied = #targetSlotIndices > 0,
	}
end)

EffectResolver.RegisterEffectHandler("TeamAttackDamageBoost", function(context)
	local allies = CombatFormulas.FilterAlive(context.allies or {})
	local now = tonumber(context.now) or os.clock()
	local magnitude = math.max(0, tonumber(context.magnitude) or 0)
	local durationSeconds = math.max(0, tonumber(context.durationSeconds) or 0)
	local targetSlotIndices = {}
	for _, ally in ipairs(allies) do
		ally.damageBoostMagnitude = math.max(tonumber(ally.damageBoostMagnitude) or 0, magnitude)
		ally.damageBoostUntil = math.max(tonumber(ally.damageBoostUntil) or 0, now + durationSeconds)
		table.insert(targetSlotIndices, ally.slotIndex)
	end
	return {
		targetSlotIndices = targetSlotIndices,
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		applied = #targetSlotIndices > 0,
	}
end)

EffectResolver.RegisterEffectHandler("HealLowestAlly", function(context)
	local allies = CombatFormulas.FilterAlive(context.allies or {})
	local magnitude = math.max(0, tonumber(context.magnitude) or 0)
	local targetSlotIndices = {}
	local lowest = nil
	local lowestRatio = 2
	for _, ally in ipairs(allies) do
		local ratio = (tonumber(ally.health) or 0) / math.max(1, tonumber(ally.maxHealth) or 1)
		if ratio < lowestRatio then
			lowestRatio = ratio
			lowest = ally
		end
	end
	if lowest then
		local healAmount = math.max(1, math.floor(math.max(1, lowest.maxHealth) * magnitude))
		DamagePipeline.ApplyHealToUnit(lowest, healAmount)
		table.insert(targetSlotIndices, lowest.slotIndex)
	end
	return {
		targetSlotIndices = targetSlotIndices,
		magnitude = magnitude,
		durationSeconds = 0,
		applied = #targetSlotIndices > 0,
	}
end)

EffectResolver.RegisterEffectHandler("EnemyPartyAttackDown", function(context)
	local now = tonumber(context.now) or os.clock()
	local magnitude = math.min(0.95, math.max(0, tonumber(context.magnitude) or 0))
	local durationSeconds = math.max(0, tonumber(context.durationSeconds) or 0)

	if context.mode == "Npc" then
		local session = context.session
		if not session then
			return { targetSlotIndices = {}, magnitude = magnitude, durationSeconds = durationSeconds, applied = false }
		end
		session.npcOutgoingAttackDebuffPercent = math.max(tonumber(session.npcOutgoingAttackDebuffPercent) or 0, magnitude)
		session.npcOutgoingAttackDebuffUntil = math.max(tonumber(session.npcOutgoingAttackDebuffUntil) or 0, now + durationSeconds)
		return {
			targetSlotIndices = { 0 },
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = true,
		}
	end

	local opponents = CombatFormulas.FilterAlive(context.opponents or {})
	local targetSlotIndices = {}
	for _, target in ipairs(opponents) do
		target.outgoingAttackDebuffPercent = math.max(tonumber(target.outgoingAttackDebuffPercent) or 0, magnitude)
		target.outgoingAttackDebuffUntil = math.max(tonumber(target.outgoingAttackDebuffUntil) or 0, now + durationSeconds)
		table.insert(targetSlotIndices, target.slotIndex)
	end
	return {
		targetSlotIndices = targetSlotIndices,
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		applied = #targetSlotIndices > 0,
	}
end)

return EffectResolver
