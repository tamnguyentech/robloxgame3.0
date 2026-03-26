-- Generic per-card counters/flags keyed by abilityId (or abilityId + suffix).
-- This keeps advanced mechanics scalable as the number of abilities grows.

local CombatAbilityState = {}

local function ensureCounters(card)
	if not card then
		return nil
	end
	card.abilityCounters = card.abilityCounters or {}
	return card.abilityCounters
end

local function ensureFlags(card)
	if not card then
		return nil
	end
	card.abilityFlags = card.abilityFlags or {}
	return card.abilityFlags
end

function CombatAbilityState.getCounter(card, abilityId)
	if not card or type(abilityId) ~= "string" or abilityId == "" then
		return 0
	end
	local counters = ensureCounters(card)
	return tonumber(counters[abilityId]) or 0
end

function CombatAbilityState.setCounter(card, abilityId, value)
	if not card or type(abilityId) ~= "string" or abilityId == "" then
		return false
	end
	local counters = ensureCounters(card)
	counters[abilityId] = tonumber(value) or 0
	return true
end

function CombatAbilityState.incrementCounter(card, abilityId, delta)
	if not card or type(abilityId) ~= "string" or abilityId == "" then
		return nil
	end
	delta = tonumber(delta) or 0
	local counters = ensureCounters(card)
	local cur = tonumber(counters[abilityId]) or 0
	local next = cur + delta
	counters[abilityId] = next
	return next
end

function CombatAbilityState.getFlag(card, flagKey)
	if not card or type(flagKey) ~= "string" or flagKey == "" then
		return false
	end
	local flags = ensureFlags(card)
	return flags[flagKey] == true
end

function CombatAbilityState.setFlag(card, flagKey, value)
	if not card or type(flagKey) ~= "string" or flagKey == "" then
		return false
	end
	local flags = ensureFlags(card)
	flags[flagKey] = value == true
	return true
end

function CombatAbilityState.clearFlag(card, flagKey)
	if not card or type(flagKey) ~= "string" or flagKey == "" then
		return false
	end
	local flags = ensureFlags(card)
	flags[flagKey] = false
	return true
end

return CombatAbilityState

