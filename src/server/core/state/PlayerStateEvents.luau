-- Why: Keep remote-event creation and client stat synchronization out of the pure state modules.
-- How: Use this module only when a state change must be broadcast to the client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStateEvents = {}

-- Why: Reuse one remote-event instance instead of creating duplicate remotes from scattered call sites.
-- How: Call this before firing a stats update to fetch or create the shared StatsUpdatedEvent.
local function getOrCreateStatsUpdatedEvent()
	local statsEvent = ReplicatedStorage:FindFirstChild("StatsUpdatedEvent")
	if not (statsEvent and statsEvent:IsA("RemoteEvent")) then
		if statsEvent then
			statsEvent:Destroy()
		end
		statsEvent = Instance.new("RemoteEvent")
		statsEvent.Name = "StatsUpdatedEvent"
		statsEvent.Parent = ReplicatedStorage
	end
	return statsEvent
end

-- Why: Send the latest stats to the owning client after a server-side stat mutation that needs immediate UI sync.
-- How: Pass a userId and a stats table; this returns true when a player was found and updated.
function PlayerStateEvents.SyncStatsToPlayer(userId, stats)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return false
	end
	getOrCreateStatsUpdatedEvent():FireClient(player, table.clone(stats or {}))
	return true
end

return PlayerStateEvents
