local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyClient = require(script.Parent.Parent:WaitForChild("services"):WaitForChild("EconomyClient"))
local ShopCatalog = require(script.Parent:WaitForChild("ShopCatalog"))
local ShopRenderer = require(script.Parent:WaitForChild("ShopRenderer"))
local BoosterPackSystem = require(script.Parent.Parent:WaitForChild("BoosterPackSystem"))
local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local RarityConfig = require(script.Parent.Parent:WaitForChild("RarityConfig"))
-- Why: Bridge gives ShopUIController access to the shared HoverPreview panel
-- that InventoryController already initialized, without creating a second instance.
local HoverPreviewBridge = require(script.Parent.Parent:WaitForChild("ui"):WaitForChild("HoverPreviewBridge"))
local DeviceContext = require(script.Parent.Parent.core:WaitForChild("DeviceContext"))

local ShopUIController = {}

local function getCurrencyValueObject()
	local valueObj = ReplicatedStorage:FindFirstChild("PlayerCurrencyValue")
	if not (valueObj and valueObj:IsA("IntValue")) then
		if valueObj then
			valueObj:Destroy()
		end
		valueObj = Instance.new("IntValue")
		valueObj.Name = "PlayerCurrencyValue"
		valueObj.Value = 0
		valueObj.Parent = ReplicatedStorage
	end
	return valueObj
end

local function resetButtonAfterDelay(button, text, delaySeconds)
	task.delay(delaySeconds, function()
		if button and button.Parent then
			button.Text = text
		end
	end)
end

function ShopUIController.Setup(contentFrame)
	if not contentFrame then
		warn("[ShopUIController] No content frame provided")
		return
	end

	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local currencyValue = getCurrencyValueObject()
	ShopRenderer.CreateCurrencyPanel(contentFrame, currencyValue)

	local tabs = ShopCatalog.GetTabs()
	local contentArea = ShopRenderer.CreateContentArea(contentFrame)
	local tabFrames = {}
	local tabBar = nil

	local function onPurchase(entry, button)
		button.Text = "Buying..."
		local ok, result = EconomyClient.Request(entry.Action, entry.Payload)
		if ok then
			button.Text = "Purchased!"
			if entry.Action == "BuyPack" then
				BoosterPackSystem.LoadOwnedSnapshot(result.state and result.state.boosterPacks or {})
			end
			resetButtonAfterDelay(button, "Buy", 0.9)
		else
			button.Text = tostring(result) == "InsufficientCoins" and "Need Coins" or "Failed"
			resetButtonAfterDelay(button, "Buy", 1.2)
		end
	end

	local function setActiveTab(tabId)
		for id, frame in pairs(tabFrames) do
			frame.Visible = id == tabId
		end
		if tabBar then
			tabBar.SetActive(tabId)
		end
	end

	for _, tab in ipairs(tabs) do
		-- CreateScrollTab now returns { scroll, grid }:
		--   scroll  – the root ScrollingFrame (used for tab visibility toggling)
		--   grid    – the inner Frame housing UIGridLayout (product cards go here)
		local tabResult = ShopRenderer.CreateScrollTab(contentArea, tab)
		tabFrames[tab.Id] = tabResult.scroll

		for _, entry in ipairs(tab.Entries) do
			local productCard = ShopRenderer.CreateProductCard(tabResult.grid, entry, onPurchase)

			-- Attach hover preview only for direct-card entries so the player can
			-- see the full card panel (including holofoil effects) without buying.
			if entry.Action == "BuyDirectCard" then
				productCard.MouseEnter:Connect(function()
					if DeviceContext.getIsMobile() then return end
					local api = HoverPreviewBridge.get()
					if not api then return end
					local data = CardDatabase.GetCardData(entry.Id)
					if not data then return end
					local rarityColor = RarityConfig.GetPreviewRarityColor(data.Rarity or "Common")
					api.Show(entry.Id, data, rarityColor)
				end)

				productCard.MouseLeave:Connect(function()
					if DeviceContext.getIsMobile() then return end
					local api = HoverPreviewBridge.get()
					if api then
						api.Hide(0.08)
					end
				end)
			end
		end

		-- Inject the Border Tier Gallery at the top of the Cards tab only.
		-- The gallery tiles are purely visual (no purchase); they use the
		-- HoverPreviewBridge module (not .get()) so the lazy call inside
		-- ShopRenderer is safe regardless of bridge initialisation order.
		if tab.Id == "Cards" then
			ShopRenderer.CreateBorderTierGallery(tabResult.scroll, HoverPreviewBridge)
		end
	end

	tabBar = ShopRenderer.CreateTabBar(contentFrame, tabs, setActiveTab)
	if tabs[1] then
		setActiveTab(tabs[1].Id)
	end
end

return ShopUIController
