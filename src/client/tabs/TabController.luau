local TabController = {}

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Fancy RPG Tab Colors
local ACTIVE_COLOR = Color3.fromRGB(80, 140, 220)
local ACTIVE_GLOW = Color3.fromRGB(100, 180, 255)
local INACTIVE_COLOR = Color3.fromRGB(45, 45, 55)
local INACTIVE_BORDER = Color3.fromRGB(90, 90, 100)
local TAB_WIDTH = 120
local TAB_HEIGHT = 38
local TAB_GAP = 10
local HEADER_BUTTON_WIDTH = 108
local HEADER_BUTTON_GAP = 8
local HEADER_TO_TABS_GAP = 12

function TabController.Init(mainUI, inventoryFrame, tabDefs)
	local existingBar = mainUI:FindFirstChild("InventoryTabBar")
	if existingBar then
		existingBar:Destroy()
	end

	-- Calculate tab bar size
	local tabBarWidth = (#tabDefs * TAB_WIDTH) + ((#tabDefs - 1) * TAB_GAP)

	local function getTabBarPosition()
		return UDim2.new(
			inventoryFrame.Position.X.Scale,
			inventoryFrame.Position.X.Offset + (inventoryFrame.Size.X.Offset / 2) - (tabBarWidth / 2),
			inventoryFrame.Position.Y.Scale,
			inventoryFrame.Position.Y.Offset - 50
		)
	end

	local tabBar = Instance.new("Frame")
	tabBar.Name = "InventoryTabBar"
	tabBar.Size = UDim2.fromOffset(tabBarWidth, TAB_HEIGHT)
	tabBar.AnchorPoint = Vector2.new(0.5, 0) -- Center anchor
	tabBar.Position = getTabBarPosition()
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = mainUI
	tabBar.ZIndex = 110

	local state = {
		tabBar = tabBar,
		framesById = {},
		buttonsById = {},
		gradientsById = {},
		activeTabId = nil,
		isVisible = true,
	}

	local function refreshVisibility()
		state.tabBar.Visible = state.isVisible
		for id, frame in pairs(state.framesById) do
			frame.Visible = state.isVisible and (id == state.activeTabId)
		end
	end

	local function setActive(tabId)
		local prevId = state.activeTabId
		state.activeTabId = tabId
		refreshVisibility()
		
		for buttonId, button in pairs(state.buttonsById) do
			local isActive = (buttonId == tabId)
			local targetColor = isActive and ACTIVE_COLOR or INACTIVE_COLOR
			local targetBorder = isActive and ACTIVE_GLOW or INACTIVE_BORDER
			
			-- Smooth color transition
			TweenService:Create(button, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
				BackgroundColor3 = targetColor
			}):Play()
			
			-- Update border
			local stroke = button:FindFirstChild("TabStroke")
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.25), {
					Color = targetBorder,
					Transparency = isActive and 0.2 or 0.5
				}):Play()
			end
			
			-- Scale active tab slightly
			local scale = isActive and 1.05 or 1.0
			local yOffset = isActive and -2 or 0
			local baseX = 0
			for i = 1, #tabDefs do
				if buttonId == tabDefs[i].GetId() then
					baseX = (i - 1) * (TAB_WIDTH + TAB_GAP)
					break
				end
			end
			TweenService:Create(button, TweenInfo.new(0.2, Enum.EasingStyle.Back), {
				Size = UDim2.fromOffset(TAB_WIDTH * scale, TAB_HEIGHT * scale),
				Position = UDim2.fromOffset(
					baseX + (TAB_WIDTH * (1 - scale) / 2),
					yOffset
				)
			}):Play()
			
			-- Animate gradient speed
			local gradient = state.gradientsById[buttonId]
			if gradient then
				gradient:SetAttribute("Speed", isActive and 0.5 or 0.2)
			end
		end
	end

	local function setVisible(isVisible)
		state.isVisible = isVisible
		refreshVisibility()
	end

	local function refreshTabBarPosition()
		if state.tabBar and state.tabBar.Parent and inventoryFrame then
			state.tabBar.Position = getTabBarPosition()
		end
	end

	inventoryFrame:GetPropertyChangedSignal("Position"):Connect(refreshTabBarPosition)
	inventoryFrame:GetPropertyChangedSignal("Size"):Connect(refreshTabBarPosition)

	-- Create fancy tab buttons
	for i, tabDef in ipairs(tabDefs) do
		local button = Instance.new("TextButton")
		button.Name = "TabButton_" .. tabDef.GetId()
		button.Size = UDim2.fromOffset(TAB_WIDTH, TAB_HEIGHT)
		button.Position = UDim2.fromOffset((i - 1) * (TAB_WIDTH + TAB_GAP), 0)
		button.BackgroundColor3 = INACTIVE_COLOR
		button.Text = tabDef.GetLabel()
		button.Font = Enum.Font.GothamBold
		button.TextSize = 15
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.BorderSizePixel = 0
		button.ZIndex = 111
		button.AutoButtonColor = false
		button.Parent = tabBar
		
		-- Rounded corners
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = button
		
		-- Text stroke for better visibility (no gradient to avoid blending)
		local textStroke = Instance.new("UIStroke")
		textStroke.Name = "TextStroke"
		textStroke.Thickness = 1
		textStroke.Color = Color3.new(0, 0, 0)
		textStroke.Transparency = 0.7
		textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		textStroke.Parent = button
		
		-- Border stroke
		local stroke = Instance.new("UIStroke")
		stroke.Name = "TabStroke"
		stroke.Thickness = 2
		stroke.Color = INACTIVE_BORDER
		stroke.Transparency = 0.5
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = button
		
		-- Hover effects
		button.MouseEnter:Connect(function()
			if state.activeTabId ~= tabDef.GetId() then
				TweenService:Create(button, TweenInfo.new(0.15), {
					BackgroundColor3 = INACTIVE_COLOR:lerp(ACTIVE_COLOR, 0.3)
				}):Play()
				TweenService:Create(stroke, TweenInfo.new(0.15), {
					Transparency = 0.3
				}):Play()
			end
		end)
		
		button.MouseLeave:Connect(function()
			if state.activeTabId ~= tabDef.GetId() then
				TweenService:Create(button, TweenInfo.new(0.15), {
					BackgroundColor3 = INACTIVE_COLOR
				}):Play()
				TweenService:Create(stroke, TweenInfo.new(0.15), {
					Transparency = 0.5
				}):Play()
			end
		end)
		
		-- Store button reference
		state.buttonsById[tabDef.GetId()] = button
	end

	local RPGHUDController = require(script.Parent.Parent.ui.controllers.RPGHUDController)
	for buttonId, button in pairs(state.buttonsById) do
		button.MouseButton1Click:Connect(function()
			setActive(buttonId)
			pcall(function()
				RPGHUDController.SwitchBackpackTab(buttonId)
			end)
		end)
	end
	
	-- Get or create content frames
	for _, tabDef in ipairs(tabDefs) do
		local contentFrame = tabDef.GetOrCreateFrame(mainUI, inventoryFrame)
		contentFrame.Visible = false
		state.framesById[tabDef.GetId()] = contentFrame
	end

	if #tabDefs > 0 then
		setActive(tabDefs[1].GetId())
	end

	return {
		SetActive = setActive,
		SetVisible = setVisible,
		RefreshLayout = refreshTabBarPosition,
		GetFrame = function(frameId)
			return state.framesById[frameId]
		end,
		GetTabBar = function()
			return state.tabBar
		end,
	}
end

return TabController
