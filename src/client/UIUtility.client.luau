local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

-- Initialize ClientStateManager first (centralized state)
local ClientStateManager = require(script.Parent.core:WaitForChild("ClientStateManager"))

-- Initialize RPG HUD System
local RPGHUDController = require(script.Parent.ui.controllers.RPGHUDController)
RPGHUDController.Init(mainUI)

-- Now populate the modals with content
local ProfileUIController = require(script.Parent.ui.controllers.ProfileUIController)
ProfileUIController.Setup(RPGHUDController.GetModalContent("Profile"))

-- InventoryUIController is deprecated – InventoryController handles UI directly
local InventoryUIController = require(script.Parent.InventoryUIController)
InventoryUIController.Setup(RPGHUDController.GetModalContent("Backpack"))

local ShopUIController = require(script.Parent.shop:WaitForChild("ShopUIController"))
ShopUIController.Setup(RPGHUDController.GetModalContent("Shop"))

local SettingsUIController = require(script.Parent.ui.controllers.SettingsUIController)
SettingsUIController.Setup(RPGHUDController.GetModalContent("Settings"))

-- EconomySnapshotEvent arrives on initial load with coins/items/boosterPacks/stats.
-- Sync into ClientStateManager so all subscribers (HUD, Profile, etc.) stay current.
local econEvent = ReplicatedStorage:FindFirstChild("EconomySnapshotEvent")
if econEvent and econEvent:IsA("RemoteEvent") then
	econEvent.OnClientEvent:Connect(function(snapshot)
		if type(snapshot) == "table" then
			ClientStateManager.syncFromServer(snapshot)
		end
	end)
end

-- InventoryController.client.luau owns the SaveDataEvent handler and calls
-- ClientStateManager.syncFromServer there. No duplicate listener needed here.
