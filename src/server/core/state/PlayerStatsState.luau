-- Why: Own all stat-related reads and writes so stat rules are not duplicated across server services.
-- How: Use these helpers for stat snapshots, stat mutation, point allocation, resets, and per-stat reads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerStateConstants = require(script.Parent:WaitForChild("PlayerStateConstants"))
local PlayerStateSchema = require(script.Parent:WaitForChild("PlayerStateSchema"))
local PlayerStateStore = require(script.Parent:WaitForChild("PlayerStateStore"))
local BalanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

local PlayerStatsState = {}

local function reconcile(state)
	state.stats = PlayerStateSchema.ReconcileStatsToLevel(state.stats, state.level)
end

-- Why: Return detached stat snapshots so callers cannot accidentally mutate live cached state.
-- How: Pass a userId and this returns a cloned stat table for that player.
function PlayerStatsState.GetStats(userId)
	local state = PlayerStateStore.GetState(userId)
	reconcile(state)
	return table.clone(state.stats)
end

-- Why: Normalize incoming stat writes through the same sanitization rules as loaded save data.
-- How: Pass a userId and a partial or full stats table; this returns the sanitized stored stat snapshot.
function PlayerStatsState.SetStats(userId, stats)
	local state = PlayerStateStore.GetState(userId)
	state.stats = PlayerStateSchema.SanitizeStats(stats, state.stats)
	reconcile(state)
	return table.clone(state.stats)
end

-- Why: Centralize stat-point validation so all callers share one source of truth for legal allocations.
-- How: Pass a userId and a stat name; returns success + cloned stats on success, or false + error code.
function PlayerStatsState.AllocateStatPoint(userId, statName)
	local state = PlayerStateStore.GetState(userId)
	if not PlayerStateConstants.IsAllocatableStat(statName) then
		return false, "InvalidStat"
	end
	reconcile(state)
	if state.stats.Points <= 0 then
		return false, "NoPoints"
	end

	state.stats[statName] = state.stats[statName] + 1
	reconcile(state)
	return true, table.clone(state.stats)
end

-- Why: Reset spendable stats in one place while refunding points from a trusted level input.
-- How: Pass a userId and a level value; this returns the cloned post-reset stats block.
function PlayerStatsState.ResetStats(userId, level)
	local state = PlayerStateStore.GetState(userId)
	local defaultStats = PlayerStateConstants.GetDefaultStats()
	state.stats = defaultStats
	-- Use the authoritative level derived from rollCount rather than trusting any
	-- caller-provided level (client can be stale, and /resetrolls mutates rollCount).
	-- Keep state.level in sync with rollCount-derived level so points are deterministic.
	local derivedLevel = math.max(1, math.floor((tonumber(state.rollCount) or 0) / BalanceConfig.ROLLS_PER_LEVEL) + 1)
	state.level = derivedLevel
	reconcile(state)
	return table.clone(state.stats)
end

-- Why: Award the level-up point without mixing in networking or remote-event concerns.
-- How: Pass a userId and this returns the cloned stats block after the point has been granted.
function PlayerStatsState.GrantLevelUpPoint(userId)
	local state = PlayerStateStore.GetState(userId)
	-- Points are derived from level; level-up systems should update state.level first.
	reconcile(state)
	return table.clone(state.stats)
end

-- Why: Expose fast scalar getters for systems that only need one stat and should avoid extra table cloning.
-- How: Pass a userId and this returns the stored Luck stat.
function PlayerStatsState.GetLuck(userId)
	return PlayerStateStore.GetState(userId).stats.Luck
end

-- Why: Expose fast scalar getters for systems that only need one stat and should avoid extra table cloning.
-- How: Pass a userId and this returns the stored RollSpeed stat.
function PlayerStatsState.GetRollSpeed(userId)
	return PlayerStateStore.GetState(userId).stats.RollSpeed
end

-- Why: Expose fast scalar getters for systems that only need one stat and should avoid extra table cloning.
-- How: Pass a userId and this returns the stored PotionDuration stat.
function PlayerStatsState.GetPotionDuration(userId)
	return PlayerStateStore.GetState(userId).stats.PotionDuration
end

-- Why: Expose fast scalar getters for systems that only need one stat and should avoid extra table cloning.
-- How: Pass a userId and this returns the stored FoilChance stat.
function PlayerStatsState.GetFoilChance(userId)
	return PlayerStateStore.GetState(userId).stats.FoilChance
end

-- Why: Expose fast scalar getters for systems that only need one stat and should avoid extra table cloning.
-- How: Pass a userId and this returns the stored unspent stat points.
function PlayerStatsState.GetPoints(userId)
	local state = PlayerStateStore.GetState(userId)
	reconcile(state)
	return state.stats.Points
end

return PlayerStatsState
