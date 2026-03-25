-- CombatFormulas.luau
-- Shared effective attack / attack interval (buff windows on unit state).

local CombatFormulas = {}

function CombatFormulas.FilterAlive(cardStates)
	local out = {}
	for _, state in ipairs(cardStates or {}) do
		if state and (tonumber(state.health) or 0) > 0 then
			table.insert(out, state)
		end
	end
	return out
end

function CombatFormulas.GetEffectiveAttack(cardState, now)
	local attack = math.max(1, math.floor(tonumber(cardState and cardState.baseAttack) or 1))
	if cardState and (tonumber(cardState.damageBoostUntil) or 0) > now then
		local boost = math.max(0, tonumber(cardState.damageBoostMagnitude) or 0)
		attack = math.max(1, math.floor(attack * (1 + boost)))
	end
	-- Outgoing attack debuff (e.g. World Champion's Bluff) — applied to attackers while active.
	if cardState and (tonumber(cardState.outgoingAttackDebuffUntil) or 0) > now then
		local pen = math.min(0.95, math.max(0, tonumber(cardState.outgoingAttackDebuffPercent) or 0))
		attack = math.max(1, math.floor(attack * (1 - pen)))
	end
	return attack
end

-- PvE NPC (non-card damage source): multiplies raw NPC attack when debuffed.
function CombatFormulas.GetEffectiveNpcOutgoingDamage(session, rawDamage, now)
	local amount = math.max(1, math.floor(tonumber(rawDamage) or 1))
	if not session then
		return amount
	end
	if (tonumber(session.npcOutgoingAttackDebuffUntil) or 0) > now then
		local pen = math.min(0.95, math.max(0, tonumber(session.npcOutgoingAttackDebuffPercent) or 0))
		amount = math.max(1, math.floor(amount * (1 - pen)))
	end
	return amount
end

CombatFormulas.GetEffectiveBossOutgoingDamage = CombatFormulas.GetEffectiveNpcOutgoingDamage

function CombatFormulas.GetEffectiveAttackInterval(cardState, now, defaultIntervalSeconds)
	local interval = math.max(0.5, tonumber(cardState and cardState.baseAttackIntervalSeconds) or defaultIntervalSeconds)
	if cardState and (tonumber(cardState.speedBoostUntil) or 0) > now then
		local boost = math.max(0, tonumber(cardState.speedBoostMagnitude) or 0)
		interval = math.max(0.25, interval / (1 + boost))
	end
	return interval
end

return CombatFormulas
