-- Why: Isolate the live player-state cache so all modules share one source of truth without duplicating storage.
-- How: Use this module whenever you need to fetch or clear a player's in-memory state.

local PlayerStateSchema = require(script.Parent:WaitForChild("PlayerStateSchema"))

local PlayerStateStore = {}

local playerStates = {}

-- Why: Lazily create player state so callers never need separate existence checks.
-- How: Pass a userId and this returns the live mutable state table for that player.
function PlayerStateStore.GetState(userId)
	if playerStates[userId] == nil then
		playerStates[userId] = PlayerStateSchema.CreateDefaultState()
	end
	return playerStates[userId]
end

-- Why: Release cached state when a player leaves so memory usage does not grow unbounded.
-- How: Pass a userId and the cached state will be removed if it exists.
function PlayerStateStore.RemoveState(userId)
	playerStates[userId] = nil
end

return PlayerStateStore
