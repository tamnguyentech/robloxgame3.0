-- StatsHandler.server.luau
-- Handles remote calls for stat point allocation system

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStatsService = require(script.Parent:WaitForChild("PlayerStatsService"))
-- Why: require SaveManager at load time so persistStats has no runtime require penalty
-- and cannot silently fail due to a missing child at call time.
local SaveManager = require(script.Parent:WaitForChild("SaveManager"))

-- Why: Get-or-create semantics prevent destroying a remote that another module
-- (PlayerStateEvents) may already own and have listeners attached to. Destroying
-- and recreating shared remotes causes timing races and silently disconnects
-- client-side WaitForChild / OnClientEvent listeners.
local function getOrCreateRemoteFunction(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = ReplicatedStorage
	return rf
end

local function getOrCreateRemoteEvent(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = ReplicatedStorage
	return re
end

local allocateRemote = getOrCreateRemoteFunction("AllocatePointsRemote")
local statsEvent = getOrCreateRemoteEvent("StatsUpdatedEvent")

local function persistStats(player)
	local ok, err = pcall(function()
		SaveManager.tryPersistPlayerData(player.UserId, player.Name)
	end)
	if not ok then
		warn("[StatsHandler] Failed to persist stats: " .. tostring(err))
	end
end

-- Handle client requests
allocateRemote.OnServerInvoke = function(player, request)
	if not player or not request then
		return nil
	end
	
	local action = request.action
	local statName = request.stat
	
	
	if action == "allocate" then
		local success, result = PlayerStatsService.AllocatePoint(player, statName)
		if success then
			statsEvent:FireClient(player, result)
			task.spawn(persistStats, player)
			return {
				Luck = result.Luck,
				RollSpeed = result.RollSpeed,
				PotionDuration = result.PotionDuration,
				FoilChance = result.FoilChance,
				Points = result.Points
			}
		else
			return nil
		end
		
	elseif action == "reset" then
		local stats = PlayerStatsService.ResetStats(player, nil)
		statsEvent:FireClient(player, stats)
		task.spawn(persistStats, player)
		return {
			Luck = stats.Luck,
			RollSpeed = stats.RollSpeed,
			PotionDuration = stats.PotionDuration,
			FoilChance = stats.FoilChance,
			Points = stats.Points
		}
		
	elseif action == "get" then
		local stats = PlayerStatsService.GetStats(player)
		return {
			Luck = stats.Luck,
			RollSpeed = stats.RollSpeed,
			PotionDuration = stats.PotionDuration,
			FoilChance = stats.FoilChance,
			Points = stats.Points
		}
		
	else
		warn(string.format("[StatsHandler] Unknown action from %s: %s", player.Name, tostring(action)))
		return nil
	end
end

