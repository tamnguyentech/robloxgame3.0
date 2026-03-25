-- ParallaxNameLabel.luau
-- 3-layer parallax name label for card names in Inventory and Hover Preview.
-- Creates a depth illusion via stacked TextLabels with offset positions.

local ParallaxNameLabel = {}

local SHADOW_OFFSET = 2
local MID_OFFSET = 1

local function createLabel(name, offsetX, offsetY, zIndex, color, parent)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Position = UDim2.fromOffset(offsetX, offsetY)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.ZIndex = zIndex
	label.Parent = parent
	return label
end

--- Create a 3-layer parallax name label container.
-- @param parent GuiObject to parent the container to
-- @param opts table with: size, position, font, textSize, textColor, zIndex, baseName
-- @return Frame container with NameShadow, NameMid, NameFront children
function ParallaxNameLabel.create(parent, opts)
	opts = opts or {}
	local size = opts.size or UDim2.new(1, 0, 0, 36)
	local position = opts.position or UDim2.fromOffset(0, 0)
	local font = opts.font or Enum.Font.Fantasy
	local textSize = opts.textSize or 24
	local textColor = opts.textColor or Color3.new(1, 1, 1)
	local baseZIndex = opts.zIndex or 10
	local baseName = opts.baseName or "NameContainer"

	local container = Instance.new("Frame")
	container.Name = baseName
	container.Size = size
	container.Position = position
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ClipsDescendants = false
	container.Parent = parent

	local shadow = createLabel("NameShadow", SHADOW_OFFSET, SHADOW_OFFSET, baseZIndex, Color3.new(0, 0, 0), container)
	local mid = createLabel("NameMid", MID_OFFSET, MID_OFFSET, baseZIndex + 1, Color3.fromRGB(80, 80, 90), container)
	local front = createLabel("NameFront", 0, 0, baseZIndex + 2, textColor, container)

	for _, lbl in ipairs({ shadow, mid, front }) do
		lbl.Font = font
		lbl.TextSize = textSize
		lbl.TextXAlignment = opts.textXAlignment or Enum.TextXAlignment.Left
		lbl.TextYAlignment = opts.textYAlignment or Enum.TextYAlignment.Top
		lbl.TextWrapped = opts.textWrapped ~= false
	end

	return container
end

--- Set text on all 3 parallax layers.
-- @param container Frame returned by create()
-- @param text string to display
function ParallaxNameLabel.setText(container, text)
	if not container or not container:IsA("Frame") then
		return
	end
	local shadow = container:FindFirstChild("NameShadow")
	local mid = container:FindFirstChild("NameMid")
	local front = container:FindFirstChild("NameFront")
	if shadow and shadow:IsA("TextLabel") then shadow.Text = text or "" end
	if mid and mid:IsA("TextLabel") then mid.Text = text or "" end
	if front and front:IsA("TextLabel") then front.Text = text or "" end
end

--- Return the front TextLabel for direct property access.
-- @param container Frame returned by create()
-- @return TextLabel|nil
function ParallaxNameLabel.getFrontLabel(container)
	if not container or not container:IsA("Frame") then
		return nil
	end
	return container:FindFirstChild("NameFront")
end

--- Check if a GuiObject is a parallax name container.
-- @param obj GuiObject
-- @return boolean
function ParallaxNameLabel.isParallaxContainer(obj)
	return obj and obj:IsA("Frame") and obj:FindFirstChild("NameFront") ~= nil
end

return ParallaxNameLabel
