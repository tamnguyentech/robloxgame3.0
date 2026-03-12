local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyProtocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EconomyProtocol"))

local EconomyClient = {}

local remotesFolder = ReplicatedStorage:WaitForChild(EconomyProtocol.Remotes.FolderName)
local requestRemote = remotesFolder:WaitForChild(EconomyProtocol.Remotes.Request)

local function ensureIntValue(name)
	local valueObj = ReplicatedStorage:FindFirstChild(name)
	if not (valueObj and valueObj:IsA("IntValue")) then
		if valueObj then
			valueObj:Destroy()
		end
		valueObj = Instance.new("IntValue")
		valueObj.Name = name
		valueObj.Value = 0
		valueObj.Parent = ReplicatedStorage
	end
	return valueObj
end

local function getOrCreateBindableEvent(name)
	local ev = ReplicatedStorage:FindFirstChild(name)
	if not (ev and ev:IsA("BindableEvent")) then
		if ev then
			ev:Destroy()
		end
		ev = Instance.new("BindableEvent")
		ev.Name = name
		ev.Parent = ReplicatedStorage
	end
	return ev
end

local function applyEconomyState(state)
	if type(state) ~= "table" then
		return
	end

	local currency = ensureIntValue("PlayerCurrencyValue")
	if type(state.coins) == "number" then
		currency.Value = math.max(0, math.floor(state.coins))
	end

	local autoRollOwned = ensureIntValue("ItemOwned_AutoRoll2x20s")
	if type(state.items) == "table" then
		autoRollOwned.Value = math.max(0, math.floor(tonumber(state.items.AutoRoll2x20s) or 0))
	else
		autoRollOwned.Value = 0
	end

	if type(state.boosterPacks) == "table" then
		getOrCreateBindableEvent("EconomySnapshotEvent"):Fire({
			boosterPacks = state.boosterPacks,
		})
	end
end

function EconomyClient.Request(actionType, payload)
	if type(actionType) ~= "string" or actionType == "" then
		return false, "Invalid action type"
	end

	local ok, response = pcall(function()
		return requestRemote:InvokeServer({
			actionType = actionType,
			payload = payload,
		})
	end)

	if not ok then
		return false, tostring(response)
	end

	if type(response) ~= "table" then
		return false, "Invalid server response"
	end

	if response.ok and type(response.state) == "table" then
		applyEconomyState(response.state)
	end

	if response.ok then
		return true, response
	end

	return false, tostring(response.reason or "RequestFailed")
end

function EconomyClient.SyncState()
	local ok, responseOrErr = EconomyClient.Request(EconomyProtocol.ActionType.GetState, {})
	if not ok then
		return false, responseOrErr
	end
	return true, responseOrErr
end

return EconomyClient
