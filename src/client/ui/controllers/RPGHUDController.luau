-- RPGHUDController.luau
-- Full-screen RPG-style HUD system with proper layout management

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local DeviceContext = require(script.Parent.Parent.Parent.core:WaitForChild("DeviceContext"))

local RPGHUDController = {}

-- Layout Constants (PC values; mobile overridden via getLayoutConstants)
local TOGGLE_BAR_WIDTH_PC = 120
local TOGGLE_BUTTON_SIZE_PC = 80
local HEADER_HEIGHT_PC = 60
local SCREEN_PADDING_PC = 20
local TOGGLE_BAR_WIDTH_MOBILE = 52
local TOGGLE_BUTTON_SIZE_MOBILE = 44
local HEADER_HEIGHT_MOBILE = 36
local SCREEN_PADDING_MOBILE = 4

local function getLayoutConstants()
	if DeviceContext.getIsMobile() then
		return {
			toggleBarWidth = TOGGLE_BAR_WIDTH_MOBILE,
			toggleButtonSize = TOGGLE_BUTTON_SIZE_MOBILE,
			headerHeight = HEADER_HEIGHT_MOBILE,
			screenPadding = SCREEN_PADDING_MOBILE,
			modalMinWidth = 280,
			modalMinHeight = 200,
		}
	end
	return {
		toggleBarWidth = TOGGLE_BAR_WIDTH_PC,
		toggleButtonSize = TOGGLE_BUTTON_SIZE_PC,
		headerHeight = HEADER_HEIGHT_PC,
		screenPadding = SCREEN_PADDING_PC,
		modalMinWidth = 320,
		modalMinHeight = 240,
	}
end

-- Combat Deck Constants (for 5 card slots; scaled down on mobile)
local COMBAT_CARD_WIDTH_PC = 140
local COMBAT_CARD_HEIGHT_PC = 210
local COMBAT_CARD_WIDTH_MOBILE = 72
local COMBAT_CARD_HEIGHT_MOBILE = 110
local COMBAT_SLOT_PADDING = 10
local COMBAT_SLOT_GAP = 10

-- Store all modals for visibility management
local activeModals = {}
local toggleBar = nil
local mainUI = nil
local updateInventorySortButtonVisibility
local updateInventorySortButtonPosition
local updateInventorySearchBarPosition
local applyModalContainerLayout
local refreshResponsiveLayout
local bindViewportLayoutUpdates
local viewportLayoutConnection
local cameraViewportConnection
local modalState = {
	IsOpen = false,
	ActiveModal = nil,
	ActiveTab = nil,
}

-- Button configurations with their corresponding modal openers (7 buttons: Backpack, Deck, Shop, Profile, Quests, Settings, Teleport)
local BUTTON_CONFIGS = {
	{
		name = "Backpack",
		text = "Backpack",
		icon = "rbxassetid://122958904701298",
		color = Color3.fromRGB(52, 92, 158),
		glow = Color3.fromRGB(0, 170, 255),
		onClick = function() RPGHUDController.ToggleModal("Backpack") end
	},
	{
		name = "Deck",
		text = "Deck",
		icon = "rbxassetid://132045995897873",
		color = Color3.fromRGB(120, 60, 180),
		glow = Color3.fromRGB(180, 100, 255),
		onClick = function() RPGHUDController.ToggleModal("Deck") end
	},
	{
		name = "Shop",
		text = "Shop",
		icon = "rbxassetid://137501891365329",
		color = Color3.fromRGB(44, 126, 72),
		glow = Color3.fromRGB(0, 255, 120),
		onClick = function() RPGHUDController.ToggleModal("Shop") end
	},
	{
		name = "Profile",
		text = "Profile",
		icon = "rbxassetid://96371461686747",
		color = Color3.fromRGB(180, 60, 120),
		glow = Color3.fromRGB(255, 0, 120),
		onClick = function() RPGHUDController.ToggleModal("Profile") end
	},
	{
		name = "Quests",
		text = "Quests",
		icon = "rbxassetid://85650247593414",
		color = Color3.fromRGB(255, 170, 0),
		glow = Color3.fromRGB(255, 255, 0),
		onClick = function() print("Quests clicked") end
	},
	{
		name = "Settings",
		text = "Settings",
		icon = "rbxassetid://71258494291704",
		color = Color3.fromRGB(120, 0, 255),
		glow = Color3.fromRGB(120, 0, 255),
		onClick = function() RPGHUDController.ToggleModal("Settings") end
	},
	{
		name = "Teleport",
		text = "Teleport",
		icon = "rbxassetid://107704790311551",
		color = Color3.fromRGB(0, 200, 255),
		glow = Color3.fromRGB(0, 200, 255),
		onClick = function() print("Teleport clicked") end
	}
}

-- Helper to get viewport size
local function getViewportSize()
	local viewport = player:FindFirstChildOfClass("PlayerGui")
	if viewport then
		local screenGui = viewport:FindFirstChild("MainUI")
		if screenGui and screenGui:IsA("ScreenGui") then
			local absSize = screenGui.AbsoluteSize
			if absSize and absSize.X > 0 then
				return absSize
			end
		end
	end
	return Vector2.new(1920, 1080) -- Default fallback
end

local function getModalBounds()
	local viewportSize = getViewportSize()
	local layout = getLayoutConstants()
	local insets = DeviceContext.getSafeInsets()
	local usableW = viewportSize.X - insets.left - insets.right
	local usableH = viewportSize.Y - insets.top - insets.bottom
	local modalWidth = math.max(layout.modalMinWidth, usableW - layout.toggleBarWidth - (layout.screenPadding * 2))
	local modalHeight = math.max(layout.modalMinHeight, usableH - (layout.screenPadding * 2))
	local modalX = layout.toggleBarWidth + layout.screenPadding + insets.left
	local modalY = layout.screenPadding + insets.top
	local contentX = modalX + 20
	local contentY = modalY + layout.headerHeight + 10
	local contentWidth = math.max(0, modalWidth - 40)
	local contentHeight = math.max(0, modalHeight - layout.headerHeight - 20)

	return {
		viewportSize = viewportSize,
		modalWidth = modalWidth,
		modalHeight = modalHeight,
		modalX = modalX,
		modalY = modalY,
		contentX = contentX,
		contentY = contentY,
		contentWidth = contentWidth,
		contentHeight = contentHeight,
		headerHeight = layout.headerHeight,
	}
end

applyModalContainerLayout = function(container, content)
	if not container then
		return
	end

	local bounds = getModalBounds()
	container.Size = UDim2.fromOffset(bounds.modalWidth, bounds.modalHeight)
	container.Position = UDim2.fromOffset(bounds.modalX, bounds.modalY)

	if content then
		content.Size = UDim2.fromOffset(bounds.contentWidth, bounds.contentHeight)
		content.Position = UDim2.fromOffset(20, bounds.headerHeight + 10)
	end
end

local VALID_MODAL_NAMES = {
	Profile = true,
	Backpack = true,
	Deck = true,
	Shop = true,
	Settings = true,
}

local VALID_BACKPACK_TABS = {
	Items = true,
	Boosters = true,
}

local VALID_INVENTORY_TABS = {
	Cards = true,
	Items = true,
	Boosters = true,
}

local function isValidModalName(name)
	return VALID_MODAL_NAMES[name] == true
end

local function isValidInventoryTab(tabId)
	return VALID_INVENTORY_TABS[tabId] == true
end

local function isValidBackpackTab(tabId)
	return VALID_BACKPACK_TABS[tabId] == true
end

local function syncBackpackTabFrames(modalData)
	if not modalData then
		return
	end

	local activeTab = modalData.ActiveTab or "Items"
	local isModalVisible = modalData.frame and modalData.frame.Visible or false
	local showItems = isModalVisible and activeTab == "Items"
	local showBoosters = isModalVisible and activeTab == "Boosters"

	if modalData.itemsFrame then
		modalData.itemsFrame.Visible = showItems
	end
	if modalData.boosterPacksFrame then
		modalData.boosterPacksFrame.Visible = showBoosters
	end

	modalData.IsOpen = isModalVisible
	modalData.ActiveModal = isModalVisible and "Backpack" or nil
	modalData.ActiveTab = activeTab
end

local function syncDeckFrames(modalData)
	if not modalData then
		return
	end

	local isModalVisible = modalData.frame and modalData.frame.Visible or false

	if modalData.inventoryFrame then
		modalData.inventoryFrame.Visible = isModalVisible
	end
	if modalData.combatDeckFrame then
		modalData.combatDeckFrame.Visible = isModalVisible
	end

	updateInventorySortButtonVisibility(modalData)
	modalData.IsOpen = isModalVisible
	modalData.ActiveModal = isModalVisible and "Deck" or nil
end

local function closeBackpackFrames(modalData)
	if not modalData then
		return
	end

	if modalData.itemsFrame then
		modalData.itemsFrame.Visible = false
	end
	if modalData.boosterPacksFrame then
		modalData.boosterPacksFrame.Visible = false
	end

	modalData.IsOpen = false
	modalData.ActiveModal = nil
	modalData.ActiveTab = nil
end

local function closeDeckFrames(modalData)
	if not modalData then
		return
	end

	if modalData.inventoryFrame then
		modalData.inventoryFrame.Visible = false
	end
	if modalData.combatDeckFrame then
		modalData.combatDeckFrame.Visible = false
	end

	modalData.IsOpen = false
	modalData.ActiveModal = nil
	updateInventorySortButtonVisibility(modalData)
	if modalState.ActiveModal == "Deck" then
		modalState.ActiveModal = nil
		modalState.IsOpen = false
	end
end

local function syncInventoryTabFrames(modalData)
	if not modalData then
		return
	end

	local activeTab = modalData.ActiveTab or "Cards"
	local isModalVisible = modalData.frame and modalData.frame.Visible or false
	local showCards = isModalVisible and activeTab == "Cards"
	local showItems = isModalVisible and activeTab == "Items"
	local showBoosters = isModalVisible and activeTab == "Boosters"

	if modalData.inventoryFrame then
		modalData.inventoryFrame.Visible = showCards
	end
	if modalData.combatDeckFrame then
		modalData.combatDeckFrame.Visible = showCards
	end
	if modalData.itemsFrame then
		modalData.itemsFrame.Visible = showItems
	end
	if modalData.boosterPacksFrame then
		modalData.boosterPacksFrame.Visible = showBoosters
	end

	updateInventorySortButtonVisibility(modalData)
	modalState.ActiveTab = modalState.ActiveModal == "Inventory" and activeTab or nil
	modalData.IsOpen = isModalVisible
	modalData.ActiveModal = isModalVisible and "Inventory" or nil
	modalData.ActiveTab = activeTab
end

local function closeInventoryFrames(modalData)
	if not modalData then
		return
	end

	if modalData.inventoryFrame then
		modalData.inventoryFrame.Visible = false
	end
	if modalData.combatDeckFrame then
		modalData.combatDeckFrame.Visible = false
	end
	if modalData.itemsFrame then
		modalData.itemsFrame.Visible = false
	end
	if modalData.boosterPacksFrame then
		modalData.boosterPacksFrame.Visible = false
	end

	modalData.IsOpen = false
	modalData.ActiveModal = nil
	modalData.ActiveTab = nil
	updateInventorySortButtonVisibility(modalData)
	if modalState.ActiveModal == "Inventory" then
		modalState.ActiveTab = nil
	end
	if modalState.ActiveModal == "Inventory" then
		modalState.ActiveModal = nil
		modalState.IsOpen = false
	end
end

-- Create the main toggle bar (vertical, left side)
local function createToggleBar(parent)
	local layoutConstants = getLayoutConstants()
	local insets = DeviceContext.getSafeInsets()
	local bar = Instance.new("Frame")
	bar.Name = "RPGToggleBar"
	bar.Size = UDim2.new(0, layoutConstants.toggleBarWidth, 1, -(insets.top + insets.bottom))
	bar.Position = UDim2.new(0, insets.left, 0, insets.top)
	bar.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.ZIndex = 1000
	bar.Parent = parent
	
	-- Gradient background
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 30, 45)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 15, 25))
	})
	gradient.Rotation = 90
	gradient.Parent = bar
	
	-- Vertical layout (use listLayout to avoid shadowing layout constants)
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = bar
	
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 20)
	padding.Parent = bar
	
	-- Create buttons using ButtonStyler for epic gradient effects
	local ButtonStyler = require(script.Parent:WaitForChild("ButtonStyler"))
	
	for i, config in ipairs(BUTTON_CONFIGS) do
		local btn = Instance.new("TextButton")
		btn.Name = config.name .. "Button"
		btn.Size = UDim2.new(0, layoutConstants.toggleButtonSize, 0, layoutConstants.toggleButtonSize)
		btn.Text = ""
		btn.Parent = bar
		
		-- Apply RPG-themed styling with epic gradient animations
		ButtonStyler.styleToggleButton(btn, config.text, config.color, config.icon, config.name)
		
		-- Click handler
		btn.MouseButton1Click:Connect(function()
			if config.onClick then
				config.onClick()
			end
		end)
	end
	
	return bar
end

-- Create a full-screen modal container
local function createModalContainer(parent, name)
	local layout = getLayoutConstants()
	local container = Instance.new("Frame")
	container.Name = name .. "Modal"
	container.Size = UDim2.fromOffset(0, 0)
	container.Position = UDim2.fromOffset(0, 0)
	container.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	container.BackgroundTransparency = 0.02
	container.BorderSizePixel = 0
	container.ZIndex = 100
	container.Visible = false
	container.Parent = parent
	
	-- Corner radius
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 20)
	corner.Parent = container
	
	-- Border
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(60, 60, 80)
	stroke.Transparency = 0.3
	stroke.Parent = container
	
	-- Shadow
	local shadow = Instance.new("ImageLabel")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.new(1, 40, 1, 40)
	shadow.Position = UDim2.new(0, -20, 0, -20)
	shadow.BackgroundTransparency = 1
	shadow.Image = "rbxassetid://466659280"
	shadow.ImageColor3 = Color3.new(0, 0, 0)
	shadow.ImageTransparency = 0.6
	shadow.ZIndex = 99
	shadow.Parent = container
	
	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, layout.headerHeight)
	header.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
	header.BorderSizePixel = 0
	header.ZIndex = 101
	header.Parent = container
	
	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 20)
	headerCorner.Parent = header
	
	-- Fix corners for header only top
	local fixFrame = Instance.new("Frame")
	fixFrame.Name = "CornerFix"
	fixFrame.Size = UDim2.new(1, 0, 0, 20)
	fixFrame.Position = UDim2.new(0, 0, 1, -20)
	fixFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 50)
	fixFrame.BorderSizePixel = 0
	fixFrame.ZIndex = 101
	fixFrame.Parent = header
	
	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -80, 1, 0)
	title.Position = UDim2.new(0, 20, 0, 0)
	title.BackgroundTransparency = 1
	title.Text = name
	title.Font = Enum.Font.GothamBold
	title.TextSize = 28
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 102
	title.Parent = header
	
	-- Close button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.new(0, 44, 0, 44)
	closeBtn.Position = UDim2.new(1, -54, 0.5, -22)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 20
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.ZIndex = 102
	closeBtn.Parent = header
	
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 12)
	closeCorner.Parent = closeBtn
	
	closeBtn.MouseButton1Click:Connect(function()
		RPGHUDController.HideModal(name)
	end)
	
	-- Content area
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.fromOffset(0, 0)
	content.Position = UDim2.fromOffset(20, layout.headerHeight + 10)
	content.BackgroundTransparency = 1
	content.ZIndex = 101
	content.Parent = container

	applyModalContainerLayout(container, content)
	
	return container, content
end

-- Initialize the HUD
function RPGHUDController.Init(parent)
	mainUI = parent
	
	-- Create toggle bar
	toggleBar = createToggleBar(mainUI)
	
	-- Create modal containers
	local profileModal, profileContent = createModalContainer(mainUI, "Profile")
	local backpackModal, backpackContent = createModalContainer(mainUI, "Backpack")
	local deckModal, deckContent = createModalContainer(mainUI, "Deck")
	local shopModal, shopContent = createModalContainer(mainUI, "Shop")
	local settingsModal, settingsContent = createModalContainer(mainUI, "Settings")
	
	activeModals = {
		Profile = { frame = profileModal, content = profileContent, IsOpen = false, ActiveModal = nil, ActiveTab = nil },
		Backpack = { frame = backpackModal, content = backpackContent, IsOpen = false, ActiveModal = nil, ActiveTab = "Items" },
		Deck = { frame = deckModal, content = deckContent, IsOpen = false, ActiveModal = nil },
		Shop = { frame = shopModal, content = shopContent, IsOpen = false, ActiveModal = nil, ActiveTab = nil },
		Settings = { frame = settingsModal, content = settingsContent, IsOpen = false, ActiveModal = nil, ActiveTab = nil }
	}

	bindViewportLayoutUpdates()
	refreshResponsiveLayout()
	
	-- Store references for InventoryController to access
	mainUI:SetAttribute("RPGHUD_BackpackModal", backpackModal.Name)
	mainUI:SetAttribute("RPGHUD_DeckModal", deckModal.Name)
	
	print("[RPGHUDController] HUD initialized - waiting for InventoryFrame")
	
	-- Wait for InventoryController to create the frames, then set them up
	task.spawn(function()
		local inventoryFrame = nil
		local combatDeckFrame = nil
		local itemsFrame = nil
		local boosterPacksFrame = nil
		local retries = 0
		
		while retries < 50 do
			inventoryFrame = mainUI:FindFirstChild("InventoryFrame")
			combatDeckFrame = mainUI:FindFirstChild("CombatDeckFrame")
			itemsFrame = mainUI:FindFirstChild("ItemsFrame")
			boosterPacksFrame = mainUI:FindFirstChild("BoosterPacksFrame")
			
			if inventoryFrame and combatDeckFrame and itemsFrame and boosterPacksFrame then
				print("[RPGHUDController] Found all frames, setting up integration")
				
				-- Backpack: items, boosters | Deck: inventory, combat deck
				activeModals.Backpack.itemsFrame = itemsFrame
				activeModals.Backpack.boosterPacksFrame = boosterPacksFrame
				activeModals.Deck.inventoryFrame = inventoryFrame
				activeModals.Deck.combatDeckFrame = combatDeckFrame
				
				-- Set up the frames for RPG HUD layout (position only, don't reparent)
				setupInventoryFramesForRPGHUD(inventoryFrame, combatDeckFrame)
				setupTabFramesForRPGHUD(itemsFrame, boosterPacksFrame)
				break
			end
			
			retries = retries + 1
			task.wait(0.1)
		end
		
		if retries >= 50 then
			warn("[RPGHUDController] Timed out waiting for frames")
		end
	end)
	
	print("[RPGHUDController] HUD initialized")
end

local createInventorySortButton
local SEARCH_BAR_HEIGHT = 36
local SEARCH_SORT_ROW_GAP = 6

local function getSearchBarHeight()
	return math.max(SEARCH_BAR_HEIGHT, DeviceContext.getTouchTargetMin())
end

-- Setup existing inventory frames to work with RPG HUD (fancy centered design)
function setupInventoryFramesForRPGHUD(inventoryFrame, combatDeckFrame)
	local bounds = getModalBounds()
	local contentX = bounds.contentX
	local contentY = bounds.contentY
	local contentWidth = bounds.contentWidth
	local contentHeight = bounds.contentHeight
	local isMobile = DeviceContext.getIsMobile()
	local inventoryMin = isMobile and 260 or 320
	local inventoryWidth = math.max(inventoryMin, math.min(isMobile and contentWidth or 780, contentWidth))
	local desiredInventoryHeight = math.floor(contentHeight * 0.58)
	local maxInventoryHeight = math.max(140, contentHeight - 140)
	local inventoryHeight = math.min(math.max(140, desiredInventoryHeight), maxInventoryHeight)
	local inventoryX = contentX + math.max(0, math.floor((contentWidth - inventoryWidth) / 2))
	local searchRowHeight = getSearchBarHeight() + SEARCH_SORT_ROW_GAP
	local inventoryY = contentY + searchRowHeight
	inventoryHeight = math.max(100, inventoryHeight - searchRowHeight)

	-- Inventory frame - centered, fancy styling (below search bar)
	inventoryFrame.Size = UDim2.fromOffset(inventoryWidth, inventoryHeight)
	inventoryFrame.Position = UDim2.fromOffset(inventoryX, inventoryY)
	inventoryFrame.Visible = false
	inventoryFrame.ZIndex = 101
	inventoryFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
	inventoryFrame.BackgroundTransparency = 0.05
	inventoryFrame.BorderSizePixel = 0
	inventoryFrame.ScrollBarThickness = 8
	inventoryFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 150, 255)
	inventoryFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	
	-- Fancy inventory styling
	local invCorner = inventoryFrame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	invCorner.CornerRadius = UDim.new(0, 16)
	invCorner.Parent = inventoryFrame
	
	local invStroke = inventoryFrame:FindFirstChild("FancyStroke") or Instance.new("UIStroke")
	invStroke.Name = "FancyStroke"
	invStroke.Thickness = 3
	invStroke.Color = Color3.fromRGB(74, 130, 225)
	invStroke.Transparency = 0.3
	invStroke.Parent = inventoryFrame
	
	-- Animated gradient background for inventory
	local invGradient = inventoryFrame:FindFirstChild("BackgroundGradient") or Instance.new("UIGradient")
	invGradient.Name = "BackgroundGradient"
	invGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 50, 70)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(30, 35, 50)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 50, 70)),
	})
	invGradient.Rotation = 0
	invGradient.Parent = inventoryFrame
	
	-- Animate the gradient
	local offset = 0
	local RunService = game:GetService("RunService")
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if not inventoryFrame or not inventoryFrame.Parent then
			connection:Disconnect()
			return
		end
		offset = (offset + dt * 0.2) % 1
		invGradient.Offset = Vector2.new(offset - 0.5, 0)
	end)
	
	-- Combat deck frame - centered, sized for exactly 5 cards, constrained to modal
	local combatCardW = isMobile and COMBAT_CARD_WIDTH_MOBILE or COMBAT_CARD_WIDTH_PC
	local combatCardH = isMobile and COMBAT_CARD_HEIGHT_MOBILE or COMBAT_CARD_HEIGHT_PC
	local maxCombatWidth = contentWidth
	local combatWidth = math.min((combatCardW * 5) + (COMBAT_SLOT_GAP * 4) + (COMBAT_SLOT_PADDING * 2), maxCombatWidth)
	local combatY = inventoryY + inventoryHeight + (isMobile and 10 or 18)
	local combatAvailableHeight = math.max(isMobile and 100 or 120, (contentY + contentHeight) - combatY)
	local combatHeight = math.min(combatCardH + (COMBAT_SLOT_PADDING * 2) + (isMobile and 24 or 40), combatAvailableHeight)
	local combatX = contentX + math.max(0, math.floor((contentWidth - combatWidth) / 2))
	
	combatDeckFrame.Size = UDim2.fromOffset(combatWidth, combatHeight)
	combatDeckFrame.Position = UDim2.fromOffset(combatX, combatY)
	combatDeckFrame.Visible = false
	combatDeckFrame.ZIndex = 101
	combatDeckFrame.BackgroundColor3 = Color3.fromRGB(45, 30, 30)
	combatDeckFrame.BackgroundTransparency = 0.05
	combatDeckFrame.BorderSizePixel = 0
	combatDeckFrame.ScrollBarThickness = 0
	combatDeckFrame.ScrollingDirection = Enum.ScrollingDirection.X
	combatDeckFrame.ClipsDescendants = true
	
	-- Fancy combat deck styling
	local combatCorner = combatDeckFrame:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	combatCorner.CornerRadius = UDim.new(0, 16)
	combatCorner.Parent = combatDeckFrame
	
	local combatStroke = combatDeckFrame:FindFirstChild("FancyStroke") or Instance.new("UIStroke")
	combatStroke.Name = "FancyStroke"
	combatStroke.Thickness = 3
	combatStroke.Color = Color3.fromRGB(225, 88, 88)
	combatStroke.Transparency = 0.3
	combatStroke.Parent = combatDeckFrame
	
	-- Animated gradient for combat deck
	local combatGradient = combatDeckFrame:FindFirstChild("BackgroundGradient") or Instance.new("UIGradient")
	combatGradient.Name = "BackgroundGradient"
	combatGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 45, 45)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(50, 35, 35)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 45, 45)),
	})
	combatGradient.Rotation = 0
	combatGradient.Parent = combatDeckFrame
	
	-- Remove existing CombatDeckLabel if present (no longer used)
	local oldLabel = combatDeckFrame:FindFirstChild("CombatDeckLabel")
	if oldLabel then
		oldLabel:Destroy()
	end

	-- Update combat slot positions for 5 unique slots
	local minSlotW = isMobile and 56 or 72
	local slotWidth = math.max(minSlotW, math.floor((combatWidth - (COMBAT_SLOT_PADDING * 2) - (COMBAT_SLOT_GAP * 4)) / 5))
	local slotHeight = math.min(combatCardH, math.max(isMobile and 80 or 96, math.floor(slotWidth * (combatCardH / combatCardW))))
	local topPad = COMBAT_SLOT_PADDING
	local maxSlotHeight = math.max(80, combatHeight - (topPad * 2))
	slotHeight = math.min(slotHeight, maxSlotHeight)
	local slotY = topPad + math.max(0, math.floor((combatHeight - (topPad * 2) - slotHeight) / 2))
	for i = 1, 5 do
		local slotName = "CombatSlot" .. i
		local slot = combatDeckFrame:FindFirstChild(slotName)
		if slot then
			slot.Size = UDim2.fromOffset(slotWidth, slotHeight)
			slot.Position = UDim2.fromOffset(
				COMBAT_SLOT_PADDING + ((i - 1) * (slotWidth + COMBAT_SLOT_GAP)),
				slotY
			)
			
			-- Fancy slot styling
			slot.BackgroundColor3 = Color3.fromRGB(35, 25, 25)
			slot.BackgroundTransparency = 0.3
			
			local slotCorner = slot:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
			slotCorner.CornerRadius = UDim.new(0, 12)
			slotCorner.Parent = slot
			
			local slotStroke = slot:FindFirstChild("SlotStroke") or Instance.new("UIStroke")
			slotStroke.Name = "SlotStroke"
			slotStroke.Thickness = 2
			slotStroke.Color = Color3.fromRGB(200, 100, 100)
			slotStroke.Transparency = 0.4
			slotStroke.Parent = slot
			
			-- Slot number indicator
			local slotNumber = slot:FindFirstChild("SlotNumber") or Instance.new("TextLabel")
			slotNumber.Name = "SlotNumber"
			slotNumber.Size = UDim2.fromOffset(24, 24)
			slotNumber.Position = UDim2.fromOffset(5, 5)
			slotNumber.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
			slotNumber.BackgroundTransparency = 0.3
			slotNumber.Text = tostring(i)
			slotNumber.TextColor3 = Color3.new(1, 1, 1)
			slotNumber.Font = Enum.Font.GothamBold
			slotNumber.TextSize = 14
			slotNumber.ZIndex = slot.ZIndex + 2
			slotNumber.Parent = slot
			
			local slotNumCorner = slotNumber:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
			slotNumCorner.CornerRadius = UDim.new(0, 6)
			slotNumCorner.Parent = slotNumber
		end
	end
	
	print("[RPGHUDController] Inventory frames positioned with fancy centered design")
	
	-- Create Search Bar for Inventory
	createInventorySearchBar(inventoryFrame)
	-- Create Sort Button for Inventory
	createInventorySortButton(inventoryFrame)
end

-- Professional Sort Button System for Inventory
local currentSortMode = "Default" -- Default, ATK, Rarity, Count
local currentSortIndex = 1 -- 1-based index into SORT_MODES for reapply after rebuild
local inventoryRebuiltConnected = false

-- Search bar state for re-apply on rebuild
local currentSearchText = ""

local function applyInventorySearchFilter(inventoryFrame, searchText)
	if not inventoryFrame or not inventoryFrame:IsA("GuiObject") then
		return
	end
	local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
	local trimmed = (searchText and type(searchText) == "string") and (string.gsub(searchText, "^%s*(.-)%s*$", "%1")) or ""
	local searchLower = trimmed ~= "" and string.lower(trimmed) or ""
	for _, child in ipairs(inventoryFrame:GetChildren()) do
		if child:IsA("GuiButton") then
			local cardId = child:GetAttribute("CardId") or child.Name
			if type(cardId) == "string" and cardId ~= "" then
				local parsed = CardDatabase.ParseCardReference(cardId)
				local baseId = parsed and parsed.BaseCardId or cardId
				local data = CardDatabase.GetCardData(baseId)
				local displayName = (data and data.Name) or baseId
				local matches = searchLower == "" or string.find(string.lower(displayName), searchLower, 1, true)
				child.Visible = matches
			else
				child.Visible = (searchLower == "")
			end
		end
	end
end

function createInventorySearchBar(inventoryFrame)
	-- Parent to Deck modal's content so search bar appears with the Deck UI (not as sibling of mainUI)
	local deckModalData = activeModals.Deck
	local searchParent = (deckModalData and deckModalData.content) or inventoryFrame.Parent
	if not searchParent then
		return
	end

	local existingSearch = searchParent:FindFirstChild("InventorySearchBar")
	if existingSearch then
		existingSearch:Destroy()
	end

	local searchBar = Instance.new("TextBox")
	searchBar.Name = "InventorySearchBar"
	searchBar.Size = UDim2.fromOffset(200, getSearchBarHeight())
	searchBar.Position = UDim2.fromOffset(0, 0)
	searchBar.AnchorPoint = Vector2.new(0, 0)
	searchBar.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
	searchBar.BorderSizePixel = 0
	searchBar.PlaceholderText = "Search cards..."
	searchBar.PlaceholderColor3 = Color3.fromRGB(140, 150, 170)
	searchBar.Text = ""
	searchBar.TextColor3 = Color3.fromRGB(255, 255, 255)
	searchBar.TextSize = 14
	searchBar.Font = Enum.Font.Gotham
	searchBar.ClearTextOnFocus = false
	searchBar.ZIndex = 110
	-- When parented to Deck content, visibility follows modal; no manual binding needed
	searchBar.Visible = true
	searchBar.Parent = searchParent

	local searchCorner = Instance.new("UICorner")
	searchCorner.CornerRadius = UDim.new(0, 8)
	searchCorner.Parent = searchBar

	local searchPadding = Instance.new("UIPadding")
	searchPadding.PaddingLeft = UDim.new(0, 12)
	searchPadding.PaddingRight = UDim.new(0, 12)
	searchPadding.Parent = searchBar

	updateInventorySearchBarPosition = function(invFrame, sb)
		sb = sb or (deckModalData and deckModalData.content and deckModalData.content:FindFirstChild("InventorySearchBar"))
			or (invFrame and invFrame.Parent and invFrame.Parent:FindFirstChild("InventorySearchBar"))
		if not invFrame or not sb then
			return
		end
		local bounds = getModalBounds()
		local invWidth = invFrame.Size.X.Offset
		local searchH = getSearchBarHeight()
		sb.Size = UDim2.fromOffset(math.max(120, invWidth - 150), searchH)
		-- Position relative to Deck content (top of content area, aligned with inventory)
		local localX = invFrame.Position.X.Offset - bounds.contentX
		local localY = 0
		sb.Position = UDim2.fromOffset(localX, localY)
	end

	updateInventorySearchBarPosition(inventoryFrame, searchBar)

	searchBar:GetPropertyChangedSignal("Text"):Connect(function()
		currentSearchText = searchBar.Text
		applyInventorySearchFilter(inventoryFrame, currentSearchText)
	end)

	searchBar.FocusLost:Connect(function()
		currentSearchText = searchBar.Text
		applyInventorySearchFilter(inventoryFrame, currentSearchText)
	end)

	-- Reapply search when inventory is rebuilt
	local invRebuilt = ReplicatedStorage:FindFirstChild("InventoryRebuiltEvent")
	if invRebuilt and invRebuilt:IsA("BindableEvent") then
		invRebuilt.Event:Connect(function()
			local deckData = activeModals.Deck
			if deckData and deckData.inventoryFrame then
				applyInventorySearchFilter(deckData.inventoryFrame, currentSearchText)
			end
		end)
	end
end

local SORT_MODES = {
	{ id = "Default", label = "Default", icon = "DEF" },
	{ id = "ATK", label = "ATK Power", icon = "ATK" },
	{ id = "Rarity", label = "Rarity", icon = "RAR" },
	{ id = "Count", label = "Card Count", icon = "CNT" }
}

local RARITY_ORDER = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	God = 6,
	Transcendent = 7
}

-- Border tier order for tiebreaking same-base-rarity cards (higher index = higher value)
local BORDER_TIER_ORDER = {"Silver", "Gold", "Diamond", "Rainbow", "Corrupted"}

local function getCardATK(cardRef)
	local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
	local ClientStateManager = require(script.Parent.Parent.Parent.core:WaitForChild("ClientStateManager"))
	local stats = ClientStateManager.getStats()
	local foilChancePoints = (stats and (stats.FoilChance or stats.BorderChance)) or 0
	return CardDatabase.GetCombatPower(cardRef, foilChancePoints)
end

local function getBorderTierIndex(tierName)
	if not tierName then
		return 0
	end
	for i, tier in ipairs(BORDER_TIER_ORDER) do
		if tier == tierName then
			return i
		end
	end
	return 0
end

local function getCardRarity(cardRef)
	local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
	local parsed = CardDatabase.ParseCardReference(cardRef)
	local baseCardId = parsed and parsed.BaseCardId or cardRef
	local cardData = CardDatabase.GetCardData(baseCardId)
	local baseRarity = 1
	if cardData and cardData.Rarity then
		baseRarity = RARITY_ORDER[cardData.Rarity] or 1
	end
	local tierIndex = getBorderTierIndex(parsed and parsed.BorderTier)
	-- Combine: primary = base rarity (1-7), secondary = border tier (0-6)
	-- Higher combined value = rarer card
	return baseRarity * 10 + tierIndex
end

local function getCardCount(card)
	local countLabel = card:FindFirstChild("NumberLabel")
	if countLabel then
		return tonumber(countLabel.Text) or 1
	end
	return 1
end

local function getOriginalOrder(card)
	return card:GetAttribute("OriginalLayoutOrder") or card.LayoutOrder or 0
end

local function isInventoryCardGui(guiObject)
	if not guiObject:IsA("GuiObject") then
		return false
	end

	if guiObject:IsA("UIGridStyleLayout") or guiObject:IsA("UIPadding") or guiObject:IsA("UICorner") or guiObject:IsA("UIStroke") or guiObject:IsA("UIGradient") then
		return false
	end

	return guiObject:GetAttribute("CardId") ~= nil or guiObject:FindFirstChild("NumberLabel") ~= nil
end

local function getCardIdFromGui(card)
	return card:GetAttribute("CardId") or card.Name
end

updateInventorySortButtonVisibility = function(modalData)
	if not modalData or not modalData.inventoryFrame then
		return
	end

	local sortButton = modalData.inventoryFrame.Parent and modalData.inventoryFrame.Parent:FindFirstChild("InventorySortButton")
	if not sortButton then
		return
	end

	-- Deck modal: sort visible when Deck is open (inventoryFrame visible)
	local isCardsTabVisible = modalData.inventoryFrame.Visible
	local isItemsVisible = modalData.itemsFrame and modalData.itemsFrame.Visible or false
	local isBoostersVisible = modalData.boosterPacksFrame and modalData.boosterPacksFrame.Visible or false
	local isModalVisible = modalData.frame and modalData.frame.Visible or false

	sortButton.Visible = isModalVisible and isCardsTabVisible and not isItemsVisible and not isBoostersVisible
	if not sortButton.Visible then
		local dropdown = sortButton:FindFirstChild("SortDropdown")
		if dropdown then
			dropdown.Visible = false
		end
	end
end

local function sortInventoryCards(inventoryFrame, sortMode, ascending)
	local cards = {}
	for _, child in ipairs(inventoryFrame:GetChildren()) do
		if isInventoryCardGui(child) then
			if child:GetAttribute("OriginalLayoutOrder") == nil then
				child:SetAttribute("OriginalLayoutOrder", child.LayoutOrder)
			end
			table.insert(cards, child)
		end
	end
	
	if sortMode == "Default" then
		table.sort(cards, function(a, b)
			return getOriginalOrder(a) < getOriginalOrder(b)
		end)
		for index, card in ipairs(cards) do
			card.LayoutOrder = index
		end
		return
	end
	
	table.sort(cards, function(a, b)
		local aValue, bValue
		local aCardId = getCardIdFromGui(a)
		local bCardId = getCardIdFromGui(b)
		
		if sortMode == "ATK" then
			aValue = getCardATK(aCardId)
			bValue = getCardATK(bCardId)
		elseif sortMode == "Rarity" then
			aValue = getCardRarity(aCardId)
			bValue = getCardRarity(bCardId)
		elseif sortMode == "Count" then
			aValue = getCardCount(a)
			bValue = getCardCount(b)
		end
		
		if aValue == bValue then
			return string.lower(aCardId) < string.lower(bCardId)
		end

		if ascending then
			return aValue < bValue
		end

		return aValue > bValue
	end)
	
	-- Reorder cards in UI
	for index, card in ipairs(cards) do
		card.LayoutOrder = index
	end
end

function createInventorySortButton(inventoryFrame)
	local modalContent = inventoryFrame.Parent
	if not modalContent then
		return
	end

	-- Remove existing sort button if any
	local existingSort = modalContent:FindFirstChild("InventorySortButton")
	if existingSort then
		existingSort:Destroy()
	end
	
	-- Sort Button Container
	local sortButton = Instance.new("TextButton")
	sortButton.Name = "InventorySortButton"
	sortButton.Size = UDim2.fromOffset(140, getSearchBarHeight())
	sortButton.Position = UDim2.fromOffset(0, 0)
	sortButton.BackgroundColor3 = Color3.fromRGB(45, 50, 65)
	sortButton.BackgroundTransparency = 0.1
	sortButton.Text = "DEF Sort: Default"
	sortButton.Font = Enum.Font.GothamBold
	sortButton.TextSize = 13
	sortButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	sortButton.ZIndex = 110
	sortButton.Visible = inventoryFrame.Visible
	sortButton.Parent = modalContent
	updateInventorySortButtonPosition(inventoryFrame, sortButton)
	
	-- Rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = sortButton
	
	-- Stroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(100, 130, 200)
	stroke.Transparency = 0.3
	stroke.Parent = sortButton
	
	local currentIndex = math.clamp(currentSortIndex, 1, #SORT_MODES)
	local function applyCurrentSort()
		currentSortIndex = currentIndex
		local mode = SORT_MODES[currentIndex]
		currentSortMode = mode.id
		sortButton.Text = mode.icon .. " Sort: " .. mode.label
		sortInventoryCards(inventoryFrame, currentSortMode, false)
	end

	sortButton.MouseButton1Click:Connect(function()
		currentIndex += 1
		if currentIndex > #SORT_MODES then
			currentIndex = 1
		end
		applyCurrentSort()
	end)
	
	-- Hover effect for sort button
	sortButton.MouseEnter:Connect(function()
		TweenService:Create(sortButton, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(55, 65, 85)}):Play()
	end)
	
	sortButton.MouseLeave:Connect(function()
		TweenService:Create(sortButton, TweenInfo.new(0.15), {BackgroundColor3 = Color3.fromRGB(45, 50, 65)}):Play()
	end)
	
	print("[RPGHUDController] Sort button created for Deck")

	local deckModalData = activeModals.Deck
	if deckModalData and not deckModalData.sortVisibilityBound then
		deckModalData.sortVisibilityBound = true
		if deckModalData.inventoryFrame then
			deckModalData.inventoryFrame:GetPropertyChangedSignal("Visible"):Connect(function()
				updateInventorySortButtonVisibility(deckModalData)
			end)
		end
		if deckModalData.frame then
			deckModalData.frame:GetPropertyChangedSignal("Visible"):Connect(function()
				updateInventorySortButtonVisibility(deckModalData)
			end)
		end
	end

	updateInventorySortButtonVisibility(deckModalData)

	-- Reapply sort when inventory is rebuilt (e.g. after selling cards) so user's preference persists
	if not inventoryRebuiltConnected then
		inventoryRebuiltConnected = true
		local invRebuilt = ReplicatedStorage:FindFirstChild("InventoryRebuiltEvent")
		if invRebuilt and invRebuilt:IsA("BindableEvent") then
			invRebuilt.Event:Connect(function()
				local deckData = activeModals.Deck
				if deckData and deckData.inventoryFrame then
					sortInventoryCards(deckData.inventoryFrame, currentSortMode, false)
				end
			end)
		end
	end
end

-- Setup tab frames (Items, Boosters) to work with RPG HUD
function setupTabFramesForRPGHUD(itemsFrame, boosterPacksFrame)
	local bounds = getModalBounds()
	local frameSize = UDim2.fromOffset(bounds.contentWidth, bounds.contentHeight)
	local framePos = UDim2.fromOffset(bounds.contentX, bounds.contentY)
	
	itemsFrame.Size = frameSize
	itemsFrame.Position = framePos
	itemsFrame.Visible = false
	itemsFrame.ZIndex = 101
	
	boosterPacksFrame.Size = frameSize
	boosterPacksFrame.Position = framePos
	boosterPacksFrame.Visible = false
	boosterPacksFrame.ZIndex = 101
	
	-- Keep BackpackContentAnchor in sync for tab bar positioning
	local backpackAnchor = mainUI:FindFirstChild("BackpackContentAnchor")
	if backpackAnchor and backpackAnchor:IsA("Frame") then
		backpackAnchor.Size = frameSize
		backpackAnchor.Position = framePos
	end
	
	print("[RPGHUDController] Tab frames positioned for RPG HUD")
end

updateInventorySortButtonPosition = function(inventoryFrame, sortButton)
	if not inventoryFrame then
		return
	end

	sortButton = sortButton or (inventoryFrame.Parent and inventoryFrame.Parent:FindFirstChild("InventorySortButton"))
	if not sortButton then
		return
	end

	sortButton.Position = UDim2.fromOffset(
		inventoryFrame.Position.X.Offset + inventoryFrame.Size.X.Offset - sortButton.Size.X.Offset,
		inventoryFrame.Position.Y.Offset - sortButton.Size.Y.Offset - 6
	)
end

refreshResponsiveLayout = function()
	if not mainUI then
		return
	end

	-- Update toggle bar for safe zone changes
	if toggleBar then
		local layout = getLayoutConstants()
		local insets = DeviceContext.getSafeInsets()
		toggleBar.Size = UDim2.new(0, layout.toggleBarWidth, 1, -(insets.top + insets.bottom))
		toggleBar.Position = UDim2.new(0, insets.left, 0, insets.top)
	end

	for _, modalData in pairs(activeModals) do
		if modalData.frame and modalData.content then
			applyModalContainerLayout(modalData.frame, modalData.content)
		end
	end

	local backpackModalData = activeModals.Backpack
	if backpackModalData and backpackModalData.itemsFrame and backpackModalData.boosterPacksFrame then
		setupTabFramesForRPGHUD(backpackModalData.itemsFrame, backpackModalData.boosterPacksFrame)
		if backpackModalData.frame and backpackModalData.frame.Visible then
			syncBackpackTabFrames(backpackModalData)
		end
	end

	local deckModalData = activeModals.Deck
	if deckModalData then
		if deckModalData.inventoryFrame and deckModalData.combatDeckFrame then
			setupInventoryFramesForRPGHUD(deckModalData.inventoryFrame, deckModalData.combatDeckFrame)
		end
		if deckModalData.frame and deckModalData.frame.Visible then
			syncDeckFrames(deckModalData)
		else
			updateInventorySortButtonVisibility(deckModalData)
		end
		if deckModalData.inventoryFrame then
			updateInventorySortButtonPosition(deckModalData.inventoryFrame)
			if updateInventorySearchBarPosition then
				updateInventorySearchBarPosition(deckModalData.inventoryFrame)
			end
		end
	end
end

bindViewportLayoutUpdates = function()
	if not mainUI then
		return
	end

	if viewportLayoutConnection then
		viewportLayoutConnection:Disconnect()
		viewportLayoutConnection = nil
	end
	viewportLayoutConnection = mainUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(refreshResponsiveLayout)
	end)

	if cameraViewportConnection then
		cameraViewportConnection:Disconnect()
		cameraViewportConnection = nil
	end

	local camera = workspace.CurrentCamera
	if camera then
		cameraViewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			task.defer(refreshResponsiveLayout)
		end)
	end

	-- Re-run layout when safe zone changes (notch, home indicator)
	DeviceContext.bindSafeZoneChanges(function()
		task.defer(refreshResponsiveLayout)
	end)
end

-- Get a modal's content frame for population
function RPGHUDController.GetModalContent(name)
	if activeModals[name] then
		return activeModals[name].content
	end
	return nil
end

function RPGHUDController.SwitchBackpackTab(tabId)
	local modalData = activeModals.Backpack
	if not modalData then
		warn("[RPGHUDController] Cannot switch backpack tab: modal data missing")
		return false
	end

	if not isValidBackpackTab(tabId) then
		warn("[RPGHUDController] Invalid backpack tab: " .. tostring(tabId))
		return false
	end

	if not modalData.frame or not modalData.frame.Visible then
		warn("[RPGHUDController] Cannot switch tabs on closed backpack modal")
		return false
	end

	modalData.ActiveTab = tabId
	modalData.IsOpen = true
	modalData.ActiveModal = "Backpack"
	modalState.IsOpen = true
	modalState.ActiveModal = "Backpack"
	syncBackpackTabFrames(modalData)
	return true
end

-- Deprecated: use SwitchBackpackTab for Backpack
function RPGHUDController.SwitchInventoryTab(tabId)
	return RPGHUDController.SwitchBackpackTab(tabId)
end

-- Show a modal
function RPGHUDController.ShowModal(name)
	if not isValidModalName(name) then
		warn("[RPGHUDController] Invalid modal: " .. tostring(name))
		return
	end

	-- Hide all other modals first
	for modalName, modalData in pairs(activeModals) do
		if modalName ~= name then
			modalData.frame.Visible = false
			if modalName == "Backpack" then
				closeBackpackFrames(modalData)
			elseif modalName == "Deck" then
				closeDeckFrames(modalData)
			else
				modalData.IsOpen = false
				modalData.ActiveModal = nil
				modalData.ActiveTab = nil
			end
		end
	end
	
	-- Show requested modal
	if activeModals[name] then
		local modalData = activeModals[name]
		refreshResponsiveLayout()
		local bounds = getModalBounds()
		modalData.frame.Visible = true
		modalData.IsOpen = true
		modalData.ActiveModal = name
		modalState.IsOpen = true
		modalState.ActiveModal = name
		
		if name == "Backpack" then
			modalData.ActiveTab = modalData.ActiveTab or "Items"
			syncBackpackTabFrames(modalData)
		elseif name == "Deck" then
			syncDeckFrames(modalData)
		else
			modalData.ActiveTab = nil
			modalState.ActiveTab = nil
		end
		
		-- Animate in
		modalData.frame.Position = UDim2.fromOffset(bounds.modalX + 20, bounds.modalY)
		modalData.frame.Size = UDim2.fromOffset(math.max(0, bounds.modalWidth - 40), bounds.modalHeight)
		TweenService:Create(modalData.frame, TweenInfo.new(0.2, Enum.EasingStyle.Back), {
			Position = UDim2.fromOffset(bounds.modalX, bounds.modalY),
			Size = UDim2.fromOffset(bounds.modalWidth, bounds.modalHeight)
		}):Play()
		print("[RPGHUDController] Showing " .. name .. " modal")
	end
end

-- Hide a modal
function RPGHUDController.HideModal(name)
	if not isValidModalName(name) then
		warn("[RPGHUDController] Invalid modal: " .. tostring(name))
		return
	end

	if activeModals[name] then
		local modalData = activeModals[name]
		
		if name == "Backpack" then
			closeBackpackFrames(modalData)
		elseif name == "Deck" then
			closeDeckFrames(modalData)
		else
			modalData.IsOpen = false
			modalData.ActiveModal = nil
			modalData.ActiveTab = nil
		end
		if modalState.ActiveModal == name then
			modalState.IsOpen = false
			modalState.ActiveModal = nil
			modalState.ActiveTab = nil
		end
		local bounds = getModalBounds()
		
		-- Animate out
		local tween = TweenService:Create(modalData.frame, TweenInfo.new(0.15), {
			Position = UDim2.fromOffset(bounds.modalX + 20, bounds.modalY),
			Size = UDim2.fromOffset(math.max(0, bounds.modalWidth - 40), bounds.modalHeight)
		})
		tween:Play()
		tween.Completed:Connect(function()
			modalData.frame.Visible = false
			applyModalContainerLayout(modalData.frame, modalData.content)
		end)
	end
end

-- Toggle a modal
function RPGHUDController.ToggleModal(name)
	if not isValidModalName(name) then
		warn("[RPGHUDController] Invalid modal: " .. tostring(name))
		return
	end

	if activeModals[name] then
		if activeModals[name].frame.Visible then
			RPGHUDController.HideModal(name)
		else
			RPGHUDController.ShowModal(name)
		end
	end
end

-- Hide all modals
function RPGHUDController.HideAllModals()
	for name, modalData in pairs(activeModals) do
		modalData.frame.Visible = false
		if name == "Backpack" then
			closeBackpackFrames(modalData)
		elseif name == "Deck" then
			closeDeckFrames(modalData)
		else
			modalData.IsOpen = false
			modalData.ActiveModal = nil
			modalData.ActiveTab = nil
		end
	end
	modalState.IsOpen = false
	modalState.ActiveModal = nil
	modalState.ActiveTab = nil
end

return RPGHUDController
