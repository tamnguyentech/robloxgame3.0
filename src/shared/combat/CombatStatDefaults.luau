-- CombatStatDefaults.luau
-- Default secondary combat stats (merge with card rows; missing fields = defaults).
--
-- Semantics (for CardDatabase rows + runtime statBlock; engine interprets in DamagePipeline later):
--   CritChance        0–100  % chance to crit on hit (before buffs).
--   CritDamage        0–500  Bonus to crit severity (e.g. +50 = +50% damage on crit); tune when wiring crit formula.
--   Accuracy          0–100  Reduces effective dodge of target (hit vs miss phase).
--   Dodge             0–100  Chance to avoid incoming attacks (mitigated by attacker Accuracy).
--   DamageReduction   0–90   % damage taken reduction (hard cap 90 to avoid invuln).
--   HealPower         0–100  Scales healing received / outgoing heal (define in resolver).
--   CooldownReduction 0–100  % reduction to ability cooldowns (future).
--   Tenacity          0–100  Resist CC / debuff duration (future).

local CombatStatDefaults = {}

local function clampStat(key, v)
	v = tonumber(v)
	if v == nil then
		return nil
	end
	if key == "CritDamage" then
		return math.max(0, math.min(500, v))
	end
	if key == "DamageReduction" then
		return math.max(0, math.min(90, v))
	end
	return math.max(0, math.min(100, v))
end

function CombatStatDefaults.GetDefaultStatBlock()
	return {
		CritChance = 0,
		CritDamage = 0,
		Accuracy = 0,
		Dodge = 0,
		DamageReduction = 0,
		HealPower = 0,
		CooldownReduction = 0,
		Tenacity = 0,
	}
end

-- Reads optional numeric fields from a card row; unknown keys ignored.
function CombatStatDefaults.ExtractStatBlockFromCardRow(data)
	local out = CombatStatDefaults.GetDefaultStatBlock()
	if type(data) ~= "table" then
		return out
	end
	for key in pairs(out) do
		local v = clampStat(key, data[key])
		if v ~= nil then
			out[key] = v
		end
	end
	return out
end

-- Shallow merge: overlay wins; nested tables not merged.
function CombatStatDefaults.MergeStatBlock(base, overlay)
	local out = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	if type(overlay) ~= "table" then
		return out
	end
	for k, v in pairs(overlay) do
		if type(v) == "number" then
			out[k] = v
		end
	end
	return out
end

return CombatStatDefaults
