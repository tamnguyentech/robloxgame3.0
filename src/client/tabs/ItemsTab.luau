local ItemsTab = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShopClient = require(script.Parent.Parent:WaitForChild("services"):WaitForChild("ShopClient"))
local BuffBridge = require(script.Parent.Parent.core:WaitForChild("BuffBridge"))

local TAB_IMAGE = "rbxassetid://0"
local AUTO_ROLL_ITEM_ID = "AutoRoll2x20s"
local LUCK_POTION_ITEM_ID = "LuckPotion"
local FOIL_CHANCE_POTION_ITEM_ID = "FoilChancePotion"

function ItemsTab.GetId()
	return "Items"
end

function ItemsTab.GetLabel()
	return "Items"
end

function ItemsTab.GetImage()
	return TAB_IMAGE
end

function ItemsTab.GetOrCreateFrame(mainUI, inventoryFrame)
	local itemsFrame = mainUI:FindFirstChild("ItemsFrame")
	if itemsFrame then
		return itemsFrame
	end

	itemsFrame = Instance.new("ScrollingFrame")
	itemsFrame.Name = "ItemsFrame"
	itemsFrame.Size = inventoryFrame.Size
	itemsFrame.Position = inventoryFrame.Position
	itemsFrame.AnchorPoint = inventoryFrame.AnchorPoint
	itemsFrame.BackgroundTransparency = inventoryFrame.BackgroundTransparency
	itemsFrame.BackgroundColor3 = inventoryFrame.BackgroundColor3
	itemsFrame.BorderSizePixel = 0
	itemsFrame.ScrollBarThickness = 8
	itemsFrame.CanvasSize = UDim2.fromOffset(0, 300)
	itemsFrame.Visible = false
	itemsFrame.Parent = (inventoryFrame and inventoryFrame.Parent) or mainUI
	itemsFrame.ZIndex = 101

	local buffEvent = ReplicatedStorage:FindFirstChild("AutoRollBuffEvent")
	if not buffEvent then
		buffEvent = Instance.new("BindableEvent")
		buffEvent.Name = "AutoRollBuffEvent"
		buffEvent.Parent = ReplicatedStorage
	end

	local luckBuffEvent = BuffBridge.GetLuckBuffEvent()
	local foilChanceBuffEvent = BuffBridge.GetFoilChanceBuffEvent()

	local ownedValue = ReplicatedStorage:FindFirstChild("ItemOwned_AutoRoll2x20s")
	if not (ownedValue and ownedValue:IsA("IntValue")) then
		if ownedValue then
			ownedValue:Destroy()
		end
		ownedValue = Instance.new("IntValue")
		ownedValue.Name = "ItemOwned_AutoRoll2x20s"
		ownedValue.Value = 0
		ownedValue.Parent = ReplicatedStorage
	end

	local luckPotionOwnedValue = ReplicatedStorage:FindFirstChild("ItemOwned_LuckPotion")
	if not (luckPotionOwnedValue and luckPotionOwnedValue:IsA("IntValue")) then
		if luckPotionOwnedValue then
			luckPotionOwnedValue:Destroy()
		end
		luckPotionOwnedValue = Instance.new("IntValue")
		luckPotionOwnedValue.Name = "ItemOwned_LuckPotion"
		luckPotionOwnedValue.Value = 0
		luckPotionOwnedValue.Parent = ReplicatedStorage
	end

	local foilChancePotionOwnedValue = ReplicatedStorage:FindFirstChild("ItemOwned_FoilChancePotion")
	if not (foilChancePotionOwnedValue and foilChancePotionOwnedValue:IsA("IntValue")) then
		if foilChancePotionOwnedValue then
			foilChancePotionOwnedValue:Destroy()
		end
		foilChancePotionOwnedValue = Instance.new("IntValue")
		foilChancePotionOwnedValue.Name = "ItemOwned_FoilChancePotion"
		foilChancePotionOwnedValue.Value = 0
		foilChancePotionOwnedValue.Parent = ReplicatedStorage
	end

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, -20, 0, 36)
	titleLabel.Position = UDim2.fromOffset(10, 8)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Owned Items"
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Font = Enum.Font.SourceSansBold
	titleLabel.TextSize = 24
	titleLabel.Parent = itemsFrame

	local row = Instance.new("Frame")
	row.Name = "AutoRollBoostRow"
	row.Size = UDim2.new(1, -20, 0, 74)
	row.Position = UDim2.fromOffset(10, 52)
	row.BackgroundColor3 = Color3.fromRGB(38, 38, 44)
	row.BorderSizePixel = 0
	row.Parent = itemsFrame

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 8)
	rowCorner.Parent = row

	local icon = Instance.new("ImageLabel")
	icon.Name = "ItemIcon"
	icon.Size = UDim2.fromOffset(56, 56)
	icon.Position = UDim2.fromOffset(8, 9)
	icon.BackgroundColor3 = Color3.fromRGB(52, 52, 60)
	icon.BorderSizePixel = 0
	icon.Image = "rbxassetid://72066453841625"
	icon.Parent = row

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(0, 6)
	iconCorner.Parent = icon

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ItemName"
	nameLabel.Size = UDim2.new(1, -220, 0, 28)
	nameLabel.Position = UDim2.fromOffset(72, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "2x Auto Roll Boost"
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Font = Enum.Font.SourceSansBold
	nameLabel.TextSize = 20
	nameLabel.Parent = row

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "ItemDesc"
	descLabel.Size = UDim2.new(1, -300, 0, 24)
	descLabel.Position = UDim2.fromOffset(72, 38)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = "Doubles auto-roll speed for 20 seconds"
	descLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Font = Enum.Font.SourceSans
	descLabel.TextSize = 17
	descLabel.Parent = row

	local ownedLabel = Instance.new("TextLabel")
	ownedLabel.Name = "OwnedLabel"
	ownedLabel.Size = UDim2.fromOffset(92, 24)
	ownedLabel.Position = UDim2.new(1, -236, 0.5, -12)
	ownedLabel.BackgroundTransparency = 1
	ownedLabel.Text = "Owned: 0"
	ownedLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
	ownedLabel.TextXAlignment = Enum.TextXAlignment.Left
	ownedLabel.Font = Enum.Font.SourceSansBold
	ownedLabel.TextSize = 17
	ownedLabel.Parent = row


	local useButton = Instance.new("TextButton")
	useButton.Name = "UseButton"
	useButton.Size = UDim2.fromOffset(132, 40)
	useButton.Position = UDim2.new(1, -142, 0.5, -20)
	useButton.BackgroundColor3 = Color3.fromRGB(70, 70, 74)
	useButton.BorderSizePixel = 0
	useButton.TextColor3 = Color3.new(1, 1, 1)
	useButton.Font = Enum.Font.SourceSansBold
	useButton.TextSize = 18
	useButton.Text = "Use"
	useButton.AutoButtonColor = false
	useButton.Parent = row

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 7)
	buttonCorner.Parent = useButton

	local function refreshOwnedUi()
		local ownedCount = ownedValue.Value
		ownedLabel.Text = "Owned: " .. tostring(ownedCount)
		local canUse = ownedCount > 0
		useButton.Active = canUse
		useButton.AutoButtonColor = canUse
		useButton.BackgroundColor3 = canUse and Color3.fromRGB(65, 118, 195) or Color3.fromRGB(70, 70, 74)
	end

	useButton.MouseButton1Click:Connect(function()
		if ownedValue.Value <= 0 then
			return
		end

		local ok, responseOrErr = ShopClient.UseItem(AUTO_ROLL_ITEM_ID, 1)
		useButton.Text = ok and "Used!" or "Failed"
		if ok and type(responseOrErr.effect) == "table" and responseOrErr.effect.type == "AutoRoll" then
			buffEvent:Fire(responseOrErr.effect)
		end
		task.delay(0.4, function()
			if useButton and useButton.Parent then
				useButton.Text = "Use"
			end
		end)
	end)

	ownedValue:GetPropertyChangedSignal("Value"):Connect(refreshOwnedUi)

	refreshOwnedUi()

	local luckRow = Instance.new("Frame")
	luckRow.Name = "LuckPotionRow"
	luckRow.Size = UDim2.new(1, -20, 0, 74)
	luckRow.Position = UDim2.fromOffset(10, 136)
	luckRow.BackgroundColor3 = Color3.fromRGB(44, 34, 56)
	luckRow.BorderSizePixel = 0
	luckRow.Parent = itemsFrame

	local luckRowCorner = Instance.new("UICorner")
	luckRowCorner.CornerRadius = UDim.new(0, 8)
	luckRowCorner.Parent = luckRow

	local luckIcon = Instance.new("ImageLabel")
	luckIcon.Name = "ItemIcon"
	luckIcon.Size = UDim2.fromOffset(56, 56)
	luckIcon.Position = UDim2.fromOffset(8, 9)
	luckIcon.BackgroundColor3 = Color3.fromRGB(70, 52, 84)
	luckIcon.BorderSizePixel = 0
	luckIcon.Image = "rbxassetid://6031075931"
	luckIcon.Parent = luckRow

	local luckIconCorner = Instance.new("UICorner")
	luckIconCorner.CornerRadius = UDim.new(0, 6)
	luckIconCorner.Parent = luckIcon

	local luckNameLabel = Instance.new("TextLabel")
	luckNameLabel.Name = "ItemName"
	luckNameLabel.Size = UDim2.new(1, -220, 0, 28)
	luckNameLabel.Position = UDim2.fromOffset(72, 8)
	luckNameLabel.BackgroundTransparency = 1
	luckNameLabel.Text = "Luck Potion"
	luckNameLabel.TextColor3 = Color3.new(1, 1, 1)
	luckNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	luckNameLabel.Font = Enum.Font.SourceSansBold
	luckNameLabel.TextSize = 20
	luckNameLabel.Parent = luckRow

	local luckDescLabel = Instance.new("TextLabel")
	luckDescLabel.Name = "ItemDesc"
	luckDescLabel.Size = UDim2.new(1, -300, 0, 24)
	luckDescLabel.Position = UDim2.fromOffset(72, 38)
	luckDescLabel.BackgroundTransparency = 1
	luckDescLabel.Text = "Boosts luck for 180 seconds. Duration scales with Potion Duration."
	luckDescLabel.TextColor3 = Color3.fromRGB(220, 210, 235)
	luckDescLabel.TextXAlignment = Enum.TextXAlignment.Left
	luckDescLabel.Font = Enum.Font.SourceSans
	luckDescLabel.TextSize = 17
	luckDescLabel.Parent = luckRow

	local luckOwnedLabel = Instance.new("TextLabel")
	luckOwnedLabel.Name = "OwnedLabel"
	luckOwnedLabel.Size = UDim2.fromOffset(92, 24)
	luckOwnedLabel.Position = UDim2.new(1, -236, 0.5, -12)
	luckOwnedLabel.BackgroundTransparency = 1
	luckOwnedLabel.Text = "Owned: 0"
	luckOwnedLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
	luckOwnedLabel.TextXAlignment = Enum.TextXAlignment.Left
	luckOwnedLabel.Font = Enum.Font.SourceSansBold
	luckOwnedLabel.TextSize = 17
	luckOwnedLabel.Parent = luckRow

	local luckUseButton = Instance.new("TextButton")
	luckUseButton.Name = "UseButton"
	luckUseButton.Size = UDim2.fromOffset(132, 40)
	luckUseButton.Position = UDim2.new(1, -142, 0.5, -20)
	luckUseButton.BackgroundColor3 = Color3.fromRGB(88, 64, 148)
	luckUseButton.BorderSizePixel = 0
	luckUseButton.TextColor3 = Color3.new(1, 1, 1)
	luckUseButton.Font = Enum.Font.SourceSansBold
	luckUseButton.TextSize = 18
	luckUseButton.Text = "Use"
	luckUseButton.AutoButtonColor = false
	luckUseButton.Parent = luckRow

	local luckButtonCorner = Instance.new("UICorner")
	luckButtonCorner.CornerRadius = UDim.new(0, 7)
	luckButtonCorner.Parent = luckUseButton

	local function refreshLuckOwnedUi()
		local ownedCount = luckPotionOwnedValue.Value
		luckOwnedLabel.Text = "Owned: " .. tostring(ownedCount)
		local canUse = ownedCount > 0
		luckUseButton.Active = canUse
		luckUseButton.AutoButtonColor = canUse
		luckUseButton.BackgroundColor3 = canUse and Color3.fromRGB(120, 82, 210) or Color3.fromRGB(70, 70, 74)
	end

	luckUseButton.MouseButton1Click:Connect(function()
		if luckPotionOwnedValue.Value <= 0 then
			return
		end

		local ok, responseOrErr = ShopClient.UseItem(LUCK_POTION_ITEM_ID, 1)
		luckUseButton.Text = ok and "Used!" or "Failed"
		if ok and type(responseOrErr.effect) == "table" then
			if responseOrErr.effect.type == "Luck" then
				-- Fire the dedicated luck-buff event so IdleCardGainer can show
				-- the HUD timer in the same area as the 2x AutoRoll buff.
				luckBuffEvent:Fire(responseOrErr.effect)
			end
		end
		task.delay(0.4, function()
			if luckUseButton and luckUseButton.Parent then
				luckUseButton.Text = "Use"
			end
		end)
	end)

	luckPotionOwnedValue:GetPropertyChangedSignal("Value"):Connect(refreshLuckOwnedUi)

	refreshLuckOwnedUi()

	-- ── Border Chance Potion row ──────────────────────────────────────────────
	local borderRow = Instance.new("Frame")
	borderRow.Name = "FoilChancePotionRow"
	borderRow.Size = UDim2.new(1, -20, 0, 74)
	borderRow.Position = UDim2.fromOffset(10, 220)
	borderRow.BackgroundColor3 = Color3.fromRGB(30, 44, 56)
	borderRow.BorderSizePixel = 0
	borderRow.Parent = itemsFrame

	local borderRowCorner = Instance.new("UICorner")
	borderRowCorner.CornerRadius = UDim.new(0, 8)
	borderRowCorner.Parent = borderRow

	local borderIcon = Instance.new("ImageLabel")
	borderIcon.Name = "ItemIcon"
	borderIcon.Size = UDim2.fromOffset(56, 56)
	borderIcon.Position = UDim2.fromOffset(8, 9)
	borderIcon.BackgroundColor3 = Color3.fromRGB(34, 62, 84)
	borderIcon.BorderSizePixel = 0
	borderIcon.Image = "rbxassetid://6031225819"
	borderIcon.Parent = borderRow

	local borderIconCorner = Instance.new("UICorner")
	borderIconCorner.CornerRadius = UDim.new(0, 6)
	borderIconCorner.Parent = borderIcon

	local borderNameLabel = Instance.new("TextLabel")
	borderNameLabel.Name = "ItemName"
	borderNameLabel.Size = UDim2.new(1, -220, 0, 28)
	borderNameLabel.Position = UDim2.fromOffset(72, 8)
	borderNameLabel.BackgroundTransparency = 1
	borderNameLabel.Text = "Foil Chance Potion"
	borderNameLabel.TextColor3 = Color3.new(1, 1, 1)
	borderNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	borderNameLabel.Font = Enum.Font.SourceSansBold
	borderNameLabel.TextSize = 20
	borderNameLabel.Parent = borderRow

	local borderDescLabel = Instance.new("TextLabel")
	borderDescLabel.Name = "ItemDesc"
	borderDescLabel.Size = UDim2.new(1, -300, 0, 24)
	borderDescLabel.Position = UDim2.fromOffset(72, 38)
	borderDescLabel.BackgroundTransparency = 1
	borderDescLabel.Text = "Boosts border chance for 180 seconds. Duration scales with Potion Duration."
	borderDescLabel.TextColor3 = Color3.fromRGB(210, 225, 235)
	borderDescLabel.TextXAlignment = Enum.TextXAlignment.Left
	borderDescLabel.Font = Enum.Font.SourceSans
	borderDescLabel.TextSize = 17
	borderDescLabel.Parent = borderRow

	local borderOwnedLabel = Instance.new("TextLabel")
	borderOwnedLabel.Name = "OwnedLabel"
	borderOwnedLabel.Size = UDim2.fromOffset(92, 24)
	borderOwnedLabel.Position = UDim2.new(1, -236, 0.5, -12)
	borderOwnedLabel.BackgroundTransparency = 1
	borderOwnedLabel.Text = "Owned: 0"
	borderOwnedLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
	borderOwnedLabel.TextXAlignment = Enum.TextXAlignment.Left
	borderOwnedLabel.Font = Enum.Font.SourceSansBold
	borderOwnedLabel.TextSize = 17
	borderOwnedLabel.Parent = borderRow

	local borderUseButton = Instance.new("TextButton")
	borderUseButton.Name = "UseButton"
	borderUseButton.Size = UDim2.fromOffset(132, 40)
	borderUseButton.Position = UDim2.new(1, -142, 0.5, -20)
	borderUseButton.BackgroundColor3 = Color3.fromRGB(70, 70, 74)
	borderUseButton.BorderSizePixel = 0
	borderUseButton.TextColor3 = Color3.new(1, 1, 1)
	borderUseButton.Font = Enum.Font.SourceSansBold
	borderUseButton.TextSize = 18
	borderUseButton.Text = "Use"
	borderUseButton.AutoButtonColor = false
	borderUseButton.Parent = borderRow

	local borderButtonCorner = Instance.new("UICorner")
	borderButtonCorner.CornerRadius = UDim.new(0, 7)
	borderButtonCorner.Parent = borderUseButton

	local function refreshBorderOwnedUi()
		local ownedCount = foilChancePotionOwnedValue.Value
		borderOwnedLabel.Text = "Owned: " .. tostring(ownedCount)
		local canUse = ownedCount > 0
		borderUseButton.Active = canUse
		borderUseButton.AutoButtonColor = canUse
		borderUseButton.BackgroundColor3 = canUse and Color3.fromRGB(38, 112, 168) or Color3.fromRGB(70, 70, 74)
	end

	borderUseButton.MouseButton1Click:Connect(function()
		if foilChancePotionOwnedValue.Value <= 0 then
			return
		end

		local ok, responseOrErr = ShopClient.UseItem(FOIL_CHANCE_POTION_ITEM_ID, 1)
		borderUseButton.Text = ok and "Used!" or "Failed"
		if ok and type(responseOrErr.effect) == "table" then
			if responseOrErr.effect.type == "FoilChance" then
				foilChanceBuffEvent:Fire(responseOrErr.effect)
			end
		end
		task.delay(0.4, function()
			if borderUseButton and borderUseButton.Parent then
				borderUseButton.Text = "Use"
			end
		end)
	end)

	foilChancePotionOwnedValue:GetPropertyChangedSignal("Value"):Connect(refreshBorderOwnedUi)

	refreshBorderOwnedUi()

	return itemsFrame
end

return ItemsTab
