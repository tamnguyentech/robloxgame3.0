local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyProtocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EconomyProtocol"))
local ClientStateManager = require(script.Parent.Parent.core:WaitForChild("ClientStateManager"))

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

local idleEvent = getOrCreateBindableEvent("IdleCardEvent")

local function applyEconomyState(state)
	if type(state) ~= "table" then
		return
	end

	ClientStateManager.syncFromServer(state)

	local currency = ensureIntValue("PlayerCurrencyValue")
	if type(state.coins) == "number" then
		currency.Value = math.max(0, math.floor(state.coins))
	end

	local autoRollOwned = ensureIntValue("ItemOwned_AutoRoll2x20s")
	local luckPotionOwned = ensureIntValue("ItemOwned_LuckPotion")
	if type(state.items) == "table" then
		autoRollOwned.Value = math.max(0, math.floor(tonumber(state.items.AutoRoll2x20s) or 0))
		luckPotionOwned.Value = math.max(0, math.floor(tonumber(state.items.LuckPotion) or 0))
	else
		autoRollOwned.Value = 0
		luckPotionOwned.Value = 0
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

	-- Fire idleEvent when cards are granted (from packs or direct purchases)
	if response.ok and type(response.grantedCards) == "table" and #response.grantedCards > 0 then
		idleEvent:Fire({
			cardIds = response.grantedCards,
			rollCount = response.state and response.state.rollCount,
			level = response.state and response.state.level,
		})
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

-- Sell a selection of cards server-authoritatively.
-- selectionDict: { [cardRef: string] = count: number }
-- Returns (ok: boolean, responseOrReason)
-- On success, the response contains soldCoins and consumedCards.
function EconomyClient.SellCards(selectionDict)
	if type(selectionDict) ~= "table" then
		return false, "InvalidSelection"
	end
	return EconomyClient.Request(EconomyProtocol.ActionType.SellCards, {
		cards = selectionDict,
	})
end

return EconomyClient
