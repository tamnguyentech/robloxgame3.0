-- DamagePipeline.luau
-- Centralized HP / PvE NPC HP changes (future: dodge, crit, shields).

local DamagePipeline = {}

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

DamagePipeline.ApplyDamageToBoss = DamagePipeline.ApplyDamageToNpc

return DamagePipeline
