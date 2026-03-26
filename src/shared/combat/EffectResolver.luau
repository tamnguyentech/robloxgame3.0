-- EffectResolver: handlers for AutoTimer and OnEntry flows (CombatAutoAbilities calls ApplyEffect).
-- On-hit-only effects are handled in CombatOnHitAbilities (same EffectType naming convention).

local CombatFormulas = require(script.Parent:WaitForChild("CombatFormulas"))
local DamagePipeline = require(script.Parent:WaitForChild("DamagePipeline"))
local CombatFollowUpDispatcher = require(script.Parent:WaitForChild("CombatFollowUpDispatcher"))
local CombatAbilityState = require(script.Parent:WaitForChild("CombatAbilityState"))

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

-- OnEntry: buff all allies' MaxHP (and current HP by the same delta) + buff effective attack.
-- HP is applied as non-reverting maxHealth changes (EffectResolver runs once per battle start).
EffectResolver.RegisterEffectHandler("HamonMentorOnEntry", function(context)
	local allies = CombatFormulas.FilterAlive(context.allies or {})
	local now = tonumber(context.now) or os.clock()
	local magnitude = math.max(0, tonumber(context.magnitude) or 0.1)
	local durationSeconds = math.max(0, tonumber(context.durationSeconds) or 0)

	local targetSlotIndices = {}
	for _, ally in ipairs(allies) do
		local curMax = math.max(1, tonumber(ally.maxHealth) or tonumber(ally.health) or 1)
		local delta = math.floor(curMax * magnitude)
		delta = math.max(0, delta)

		ally.maxHealth = curMax + delta
		local curHp = tonumber(ally.health) or curMax
		ally.health = math.min(ally.maxHealth, curHp + delta)

		-- ATK: use the existing effective-attack multiplier window.
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

EffectResolver.RegisterEffectHandler("EnemyIncomingDamageVulnerability", function(context)
	local now = tonumber(context.now) or os.clock()
	local magnitude = math.min(2, math.max(0, tonumber(context.magnitude) or 0))
	local durationSeconds = math.max(0, tonumber(context.durationSeconds) or 0)

	if context.mode == "Npc" then
		local session = context.session
		if not session then
			return { targetSlotIndices = {}, magnitude = magnitude, durationSeconds = durationSeconds, applied = false }
		end
		session.npcIncomingDamageBonusFraction = math.max(tonumber(session.npcIncomingDamageBonusFraction) or 0, magnitude)
		session.npcIncomingDamageBonusUntil = math.max(tonumber(session.npcIncomingDamageBonusUntil) or 0, now + durationSeconds)
		return {
			targetSlotIndices = { 0 },
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = true,
		}
	end

	local opponents = CombatFormulas.FilterAlive(context.opponents or {})
	if #opponents == 0 then
		return {
			targetSlotIndices = {},
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = false,
		}
	end

	local target = opponents[math.random(1, #opponents)]
	target.incomingDamageBonusFraction = math.max(tonumber(target.incomingDamageBonusFraction) or 0, magnitude)
	target.incomingDamageBonusUntil = math.max(tonumber(target.incomingDamageBonusUntil) or 0, now + durationSeconds)
	return {
		targetSlotIndices = { target.slotIndex },
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		applied = true,
	}
end)

EffectResolver.RegisterEffectHandler("LastAllyHealthShare", function(context)
	local caster = context.caster
	if not caster then
		return {
			targetSlotIndices = {},
			magnitude = tonumber(context.magnitude) or 0,
			durationSeconds = 0,
			applied = false,
		}
	end

	local aliveAllies = CombatFormulas.FilterAlive(context.allies or {})
	if #aliveAllies == 0 then
		return {
			targetSlotIndices = {},
			magnitude = tonumber(context.magnitude) or 0,
			durationSeconds = 0,
			applied = false,
		}
	end

	local magnitude = math.max(0, tonumber(context.magnitude) or 0)
	if magnitude <= 0 then
		return {
			targetSlotIndices = {},
			magnitude = 0,
			durationSeconds = 0,
			applied = false,
		}
	end

	local casterSlotIndex = tonumber(caster.slotIndex) or nil
	local casterMaxHealth = math.max(0, tonumber(caster.maxHealth) or tonumber(caster.health) or 0)

	-- "Last ally" = highest slotIndex among allies, excluding the caster.
	local target = nil
	local bestSlot = -math.huge
	for _, ally in ipairs(aliveAllies) do
		local allySlot = tonumber(ally.slotIndex) or 0
		if not (ally == caster) and not (casterSlotIndex ~= nil and allySlot == casterSlotIndex) then
			if allySlot > bestSlot then
				target = ally
				bestSlot = allySlot
			end
		end
	end

	if not target then
		return {
			targetSlotIndices = {},
			magnitude = magnitude,
			durationSeconds = 0,
			applied = false,
		}
	end

	-- At battle start, caster.health == caster.maxHealth in both PvE and PvP.
	local transfer = math.max(1, math.floor(casterMaxHealth * magnitude))
	target.maxHealth = (tonumber(target.maxHealth) or 0) + transfer
	target.health = (tonumber(target.health) or 0) + transfer

	return {
		targetSlotIndices = { target.slotIndex },
		magnitude = magnitude,
		durationSeconds = 0,
		applied = true,
	}
end)

-- OnEntry: caster gains Magnitude * reference baseAttack and Magnitude * reference maxHealth.
-- Reference = ally (including caster) with highest score = baseAttack + maxHealth; tie-break: higher slotIndex.
EffectResolver.RegisterEffectHandler("CowardScourageOnEntry", function(context)
	local caster = context.caster
	if not caster then
		return {
			targetSlotIndices = {},
			magnitude = tonumber(context.magnitude) or 0,
			durationSeconds = 0,
			applied = false,
		}
	end

	local aliveAllies = CombatFormulas.FilterAlive(context.allies or {})
	if #aliveAllies == 0 then
		return {
			targetSlotIndices = {},
			magnitude = tonumber(context.magnitude) or 0,
			durationSeconds = 0,
			applied = false,
		}
	end

	local magnitude = math.clamp(tonumber(context.magnitude) or 0.05, 0, 1)
	if magnitude <= 0 then
		return {
			targetSlotIndices = {},
			magnitude = 0,
			durationSeconds = 0,
			applied = false,
		}
	end

	local function scoreAlly(ally)
		local atk = math.max(0, math.floor(tonumber(ally.baseAttack) or 0))
		local hp = math.max(0, math.floor(tonumber(ally.maxHealth) or 0))
		return atk + hp
	end

	local function slotKey(ally)
		return tonumber(ally.slotIndex) or 0
	end

	local reference = aliveAllies[1]
	local bestScore = scoreAlly(reference)
	local bestSlot = slotKey(reference)
	for i = 2, #aliveAllies do
		local ally = aliveAllies[i]
		local s = scoreAlly(ally)
		local sk = slotKey(ally)
		if s > bestScore or (s == bestScore and sk > bestSlot) then
			bestScore = s
			bestSlot = sk
			reference = ally
		end
	end

	local refAtk = math.max(0, math.floor(tonumber(reference.baseAttack) or 0))
	local refHp = math.max(1, math.floor(tonumber(reference.maxHealth) or 1))
	local addAtk = math.max(0, math.floor(refAtk * magnitude))
	local addHp = math.max(0, math.floor(refHp * magnitude))

	local curAtk = math.max(1, math.floor(tonumber(caster.baseAttack) or 1))
	local curMax = math.max(1, math.floor(tonumber(caster.maxHealth) or 1))
	local curHp = math.max(0, math.floor(tonumber(caster.health) or 0))

	caster.baseAttack = math.max(1, curAtk + addAtk)
	caster.maxHealth = math.max(1, curMax + addHp)
	caster.health = math.min(caster.maxHealth, curHp + addHp)

	return {
		targetSlotIndices = { caster.slotIndex },
		magnitude = magnitude,
		durationSeconds = 0,
		applied = true,
	}
end)

-- OnEntry: add Dodge + speed, and set a forced dodge on the next eligible incoming attack.
EffectResolver.RegisterEffectHandler("KillerInstinctsOnEntry", function(context)
	local caster = context.caster
	local now = tonumber(context.now) or os.clock()
	local magnitude = math.max(0, math.min(1, tonumber(context.magnitude) or 0))
	local durationSeconds = math.max(0, tonumber(context.durationSeconds) or 0)

	if not caster then
		return {
			targetSlotIndices = {},
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = false,
		}
	end

	-- Forced dodge applies only to the next eligible incoming hit (not stunned / not dodge-disabled).
	caster.killerInstinctsForceDodgeNext = true -- legacy field (keep for compatibility)
	CombatAbilityState.setFlag(caster, "killerinstincts:forceDodgeNext", true)

	-- Dodge is stored in statBlock as a 0..100 percentage.
	local existingDodge = tonumber(caster.statBlock and caster.statBlock.Dodge) or 0
	local addDodge = magnitude * 100
	caster.statBlock.Dodge = math.clamp(existingDodge + addDodge, 0, 100)

	-- Attack speed boost uses the existing speedBoostMagnitude/speedBoostUntil window.
	caster.speedBoostMagnitude = math.max(tonumber(caster.speedBoostMagnitude) or 0, magnitude)
	caster.speedBoostUntil = math.max(tonumber(caster.speedBoostUntil) or 0, now + durationSeconds)

	return {
		targetSlotIndices = { caster.slotIndex },
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		applied = true,
	}
end)

EffectResolver.RegisterEffectHandler("SealOneEnemy", function(context)
	local now = tonumber(context.now) or os.clock()
	local magnitude = math.max(0, tonumber(context.magnitude) or 0)
	local durationSeconds = math.max(0, tonumber(context.durationSeconds) or 0)

	if context.mode == "Npc" then
		-- NPC mode currently has no ability-cast lockout on the NPC side.
		return {
			targetSlotIndices = {},
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = false,
		}
	end

	local opponents = CombatFormulas.FilterAlive(context.opponents or {})
	if #opponents == 0 or durationSeconds <= 0 then
		return {
			targetSlotIndices = {},
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = false,
		}
	end

	local target = opponents[math.random(1, #opponents)]
	if not target then
		return {
			targetSlotIndices = {},
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = false,
		}
	end

	target.sealUntil = math.max(tonumber(target.sealUntil) or 0, now + durationSeconds)
	return {
		targetSlotIndices = { target.slotIndex },
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		applied = true,
	}
end)

EffectResolver.RegisterEffectHandler("AntiMagicOnEntry", function(context)
	local now = tonumber(context.now) or os.clock()
	local magnitude = math.max(0, tonumber(context.magnitude) or 0)
	local durationSeconds = math.max(0, tonumber(context.durationSeconds) or 0)
	local vsMageFraction = math.clamp(tonumber(context.vsMageDamageReductionFraction) or 0, 0, 0.95)

	local caster = context.caster
	if caster and vsMageFraction > 0 then
		caster.damageReductionVsMageAttacks = math.max(tonumber(caster.damageReductionVsMageAttacks) or 0, vsMageFraction)
	end

	local targetSlotIndices = {}
	local sealed = false

	if context.mode ~= "Npc" then
		local opponents = CombatFormulas.FilterAlive(context.opponents or {})
		if #opponents > 0 and durationSeconds > 0 then
			local target = opponents[math.random(1, #opponents)]
			if target then
				target.sealUntil = math.max(tonumber(target.sealUntil) or 0, now + durationSeconds)
				table.insert(targetSlotIndices, target.slotIndex)
				sealed = true
			end
		end
	end

	local passiveApplied = caster ~= nil and vsMageFraction > 0
	return {
		targetSlotIndices = targetSlotIndices,
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		applied = sealed or passiveApplied,
	}
end)

EffectResolver.RegisterEffectHandler("StunOneEnemy", function(context)
	local now = tonumber(context.now) or os.clock()
	local magnitude = math.max(0, tonumber(context.magnitude) or 0)
	local durationSeconds = math.max(0, tonumber(context.durationSeconds) or 0)

	if context.mode == "Npc" then
		local session = context.session
		if not session or durationSeconds <= 0 then
			return {
				targetSlotIndices = {},
				magnitude = magnitude,
				durationSeconds = durationSeconds,
				applied = false,
			}
		end
		session.npcStunUntil = math.max(tonumber(session.npcStunUntil) or 0, now + durationSeconds)
		return {
			targetSlotIndices = { 0 },
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = true,
		}
	end

	local opponents = CombatFormulas.FilterAlive(context.opponents or {})
	if #opponents == 0 or durationSeconds <= 0 then
		return {
			targetSlotIndices = {},
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = false,
		}
	end

	local target = opponents[math.random(1, #opponents)]
	if not target then
		return {
			targetSlotIndices = {},
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = false,
		}
	end

	target.stunUntil = math.max(tonumber(target.stunUntil) or 0, now + durationSeconds)
	return {
		targetSlotIndices = { target.slotIndex },
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		applied = true,
	}
end)

EffectResolver.RegisterEffectHandler("StunAllEnemies", function(context)
	local now = tonumber(context.now) or os.clock()
	local magnitude = math.max(0, tonumber(context.magnitude) or 0)
	local durationSeconds = math.max(0, tonumber(context.durationSeconds) or 0)

	if context.mode == "Npc" then
		local session = context.session
		if not session or durationSeconds <= 0 then
			return {
				targetSlotIndices = {},
				magnitude = magnitude,
				durationSeconds = durationSeconds,
				applied = false,
			}
		end
		session.npcStunUntil = math.max(tonumber(session.npcStunUntil) or 0, now + durationSeconds)
		return {
			targetSlotIndices = { 0 },
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = true,
		}
	end

	local opponents = CombatFormulas.FilterAlive(context.opponents or {})
	if #opponents == 0 or durationSeconds <= 0 then
		return {
			targetSlotIndices = {},
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = false,
		}
	end

	local targetSlotIndices = {}
	for _, target in ipairs(opponents) do
		target.stunUntil = math.max(tonumber(target.stunUntil) or 0, now + durationSeconds)
		table.insert(targetSlotIndices, target.slotIndex)
	end

	return {
		targetSlotIndices = targetSlotIndices,
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		applied = #targetSlotIndices > 0,
	}
end)

EffectResolver.RegisterEffectHandler("DisableDodgeAllEnemies", function(context)
	local now = tonumber(context.now) or os.clock()
	local magnitude = math.max(0, tonumber(context.magnitude) or 0)
	local durationSeconds = math.max(0, tonumber(context.durationSeconds) or 0)

	if context.mode == "Npc" then
		-- NPC mode: target is the single NPC; dodge isn't modeled for the NPC side in PvE.
		return {
			targetSlotIndices = {},
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = false,
		}
	end

	local opponents = CombatFormulas.FilterAlive(context.opponents or {})
	if #opponents == 0 or durationSeconds <= 0 then
		return {
			targetSlotIndices = {},
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = false,
		}
	end

	local targetSlotIndices = {}
	for _, target in ipairs(opponents) do
		target.dodgeDisabledUntil = math.max(tonumber(target.dodgeDisabledUntil) or 0, now + durationSeconds)
		table.insert(targetSlotIndices, target.slotIndex)
	end

	return {
		targetSlotIndices = targetSlotIndices,
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		applied = #targetSlotIndices > 0,
	}
end)

-- Passive: DamageMultiplierOnHitProc
-- Magnitude = procChance (0-1).
-- ProcDamageBonus = bonus amount (e.g. +1.5 means total multiplier = 1 + 1.5 = 2.5).
-- DurationSeconds = how long the passive proc is active (until timestamp).
EffectResolver.RegisterEffectHandler("DamageMultiplierOnHitProc", function(context)
	local now = tonumber(context.now) or os.clock()
	local magnitude = math.max(0, tonumber(context.magnitude) or 0)
	local durationSeconds = math.max(0, tonumber(context.durationSeconds) or 0)
	local caster = context.caster

	if not caster then
		return {
			targetSlotIndices = {},
			magnitude = magnitude,
			durationSeconds = durationSeconds,
			applied = false,
		}
	end

	local procChance = math.clamp(magnitude, 0, 1)
	local procDamageBonus = math.max(0, tonumber(context.procDamageBonus) or 0)
	local procUntil = now + durationSeconds

	caster.onHitDamageProcs = caster.onHitDamageProcs or {}
	table.insert(caster.onHitDamageProcs, {
		chance = procChance,
		bonus = procDamageBonus, -- bonus amount (not total multiplier)
		untilTime = procUntil,
	})

	return {
		targetSlotIndices = { caster.slotIndex },
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		-- This effect is evaluated in `DamagePipeline` on landed hits.
		-- We intentionally suppress `abilityEvents` so the UI doesn't spam with proc-only effects.
		applied = false,
	}
end)

-- OnEntry ability:
-- - Hits a single enemy (random) multiple times.
-- - Each hit deals: enemy.baseAttack * Magnitude
-- - Applies a reduced-healing debuff to the enemy for DurationSeconds.
EffectResolver.RegisterEffectHandler("MultiHitDamageAndHealingReductionOnEntry", function(context)
	local now = tonumber(context.now) or os.clock()
	local damageFraction = math.max(0, tonumber(context.magnitude) or 0)
	local durationSeconds = math.max(0, tonumber(context.durationSeconds) or 0)
	local hitCount = math.max(1, tonumber(context.hitCount) or 1)
	local healingReductionFraction = math.clamp(tonumber(context.healingReductionFraction) or 0, 0, 1)

	local caster = context.caster
	if not caster then
		return {
			targetSlotIndices = {},
			applied = false,
		}
	end

	if context.mode == "Npc" then
		local session = context.session
		if not session then
			return {
				targetSlotIndices = {},
				applied = false,
			}
		end

		local npcAttack = math.max(1, math.floor(tonumber(session.npcAttack) or 1))
		local entryNpcAttacks = {}
		for hitIndex = 1, hitCount do
			local rawDamage = math.max(0, math.floor(npcAttack * damageFraction))
			local hitResult = DamagePipeline.ResolveHit(caster, nil, rawDamage, now)
			DamagePipeline.ApplyDamageToNpc(session, hitResult.finalDamage)
			table.insert(entryNpcAttacks, {
				attackerSlotIndex = caster.slotIndex,
				attackerCardId = caster.cardId,
				isEntryMultiHit = true,
				entryHitIndex = hitIndex,
				dealtDamage = hitResult.finalDamage,
				rawDamage = hitResult.rawDamage,
				isCrit = hitResult.isCrit,
				isDodged = hitResult.isDodged,
				absorbed = hitResult.absorbed,
				isFangFollowup = false,
			})

			local followUps = CombatFollowUpDispatcher.maybeGetFollowUps(caster, nil, hitResult, now, session)
			if followUps then
				for _, follow in ipairs(followUps) do
					DamagePipeline.ApplyDamageToNpc(session, follow.finalDamage)
					table.insert(entryNpcAttacks, {
						attackerSlotIndex = caster.slotIndex,
						attackerCardId = caster.cardId,
						isEntryMultiHit = true,
						entryHitIndex = hitIndex,
						dealtDamage = follow.finalDamage,
						rawDamage = follow.rawDamage,
						isCrit = follow.isCrit,
						isDodged = follow.isDodged,
						absorbed = follow.absorbed,
						isFangFollowup = follow.isFangFollowup == true,
						isStarburstFollowup = follow.isStarburstFollowup == true,
					})
				end
			end
		end

		-- NPC healing reduction is reserved for future NPC-heal mechanics.
		session.npcHealingReductionFraction = healingReductionFraction
		session.npcHealingReductionUntil = now + durationSeconds

		return {
			targetSlotIndices = {},
			magnitude = healingReductionFraction,
			durationSeconds = durationSeconds,
			entryNpcAttacks = entryNpcAttacks,
			applied = true,
		}
	end

	local opponents = CombatFormulas.FilterAlive(context.opponents or {})
	if #opponents == 0 or durationSeconds <= 0 then
		return {
			targetSlotIndices = {},
			applied = false,
		}
	end

	local target = opponents[math.random(1, #opponents)]
	if not target then
		return {
			targetSlotIndices = {},
			applied = false,
		}
	end

	-- Apply reduced healing debuff immediately.
	target.healingReductionFraction = healingReductionFraction
	target.healingReductionUntil = now + durationSeconds

	local targetBaseAttack = tonumber(target.baseAttack) or tonumber(target.attack) or 0
	local entryAttacks = {}
	for hitIndex = 1, hitCount do
		local rawDamage = math.max(0, math.floor(targetBaseAttack * damageFraction))
		local hitResult = DamagePipeline.ResolveHit(caster, target, rawDamage, now)
		table.insert(entryAttacks, {
			attackerSlotIndex = caster.slotIndex,
			attackerCardId = caster.cardId,
			isEntryMultiHit = true,
			entryHitIndex = hitIndex,
			targetSlotIndex = target.slotIndex,
			targetCardId = target.cardId,
			damage = hitResult.finalDamage,
			rawDamage = hitResult.rawDamage,
			isCrit = hitResult.isCrit,
			isDodged = hitResult.isDodged,
			absorbed = hitResult.absorbed,
			isFangFollowup = false,
		})

		local followUps = CombatFollowUpDispatcher.maybeGetFollowUps(caster, target, hitResult, now)
		if followUps then
			for _, follow in ipairs(followUps) do
				table.insert(entryAttacks, {
					attackerSlotIndex = caster.slotIndex,
					attackerCardId = caster.cardId,
					isEntryMultiHit = true,
					entryHitIndex = hitIndex,
					targetSlotIndex = target.slotIndex,
					targetCardId = target.cardId,
					damage = follow.finalDamage,
					rawDamage = follow.rawDamage,
					isCrit = follow.isCrit,
					isDodged = follow.isDodged,
					absorbed = follow.absorbed,
					isFangFollowup = follow.isFangFollowup == true,
					isStarburstFollowup = follow.isStarburstFollowup == true,
				})
			end
		end
	end

	return {
		targetSlotIndices = { target.slotIndex },
		magnitude = healingReductionFraction,
		durationSeconds = durationSeconds,
		entryAttacks = entryAttacks,
		applied = true,
	}
end)

return EffectResolver
