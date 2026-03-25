-- DamageNumberView.luau
-- Config-driven floating damage numbers on GuiObject parents (PvE + PvP). Style: StyleConfig.DamageNumbers.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local StyleConfig = require(script.Parent:WaitForChild("styles"):WaitForChild("StyleConfig"))

local DamageNumberView = {}

-- PvE / layered UIs: parent to battle `rootFrame` at the target's screen center so text is not occluded by sibling frames (e.g. deck row).
function DamageNumberView.showFloatingOnRoot(rootFrame, targetGui, rawAmount, kind)
	if not (rootFrame and rootFrame:IsA("GuiObject") and rootFrame.Parent and targetGui and targetGui:IsA("GuiObject") and targetGui.Parent) then
		return
	end
	local amount = math.max(0, math.floor(tonumber(rawAmount) or 0))
	if amount <= 0 then
		return
	end

	local key = kind or "Default"
	local profile = StyleConfig.DamageNumbers[key] or StyleConfig.DamageNumbers.Default
	local size = profile.Size or UDim2.fromOffset(96, 26)
	local rootAbs = rootFrame.AbsolutePosition
	local center = targetGui.AbsolutePosition + (targetGui.AbsoluteSize * 0.5)
	local cx = center.X - rootAbs.X
	local cy = center.Y - rootAbs.Y
	local y0 = cy + (tonumber(profile.RootStartOffsetY) or -12)
	local y1 = cy + (tonumber(profile.RootEndOffsetY) or -72)

	local label = Instance.new("TextLabel")
	label.Name = "DamageNumber"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = size
	label.Position = UDim2.fromOffset(cx, y0)
	label.BackgroundTransparency = 1
	label.TextTransparency = 0
	local prefix = profile.Prefix or "-"
	label.Text = prefix .. CardDatabase.FormatAttack(amount)
	label.Font = profile.Font or Enum.Font.GothamBlack
	label.TextSize = profile.TextSize or 16
	label.TextColor3 = profile.TextColor or Color3.fromRGB(255, 120, 120)
	label.TextStrokeColor3 = profile.TextStrokeColor or Color3.fromRGB(8, 8, 8)
	label.TextStrokeTransparency = profile.TextStrokeTransparency or 0
	label.ZIndex = math.max(500, profile.ZIndex or 120)
	label.Parent = rootFrame

	local dur = profile.DurationSeconds or 0.42
	TweenService:Create(
		label,
		TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromOffset(cx, y1),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	):Play()

	task.delay(dur + 0.06, function()
		if label and label.Parent then
			label:Destroy()
		end
	end)
end

function DamageNumberView.show(parent, rawAmount, kind)
	if not (parent and parent:IsA("GuiObject") and parent.Parent) then
		return
	end
	local amount = math.max(0, math.floor(tonumber(rawAmount) or 0))
	if amount <= 0 then
		return
	end

	local key = kind or "Default"
	local profile = StyleConfig.DamageNumbers[key] or StyleConfig.DamageNumbers.Default
	local size = profile.Size or UDim2.fromOffset(96, 26)

	local label = Instance.new("TextLabel")
	label.Name = "DamageNumber"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = size
	label.Position = profile.StartPosition or UDim2.fromScale(0.5, 0.42)
	label.BackgroundTransparency = 1
	local prefix = profile.Prefix or "-"
	label.Text = prefix .. CardDatabase.FormatAttack(amount)
	label.Font = profile.Font or Enum.Font.GothamBlack
	label.TextSize = profile.TextSize or 16
	label.TextColor3 = profile.TextColor or Color3.fromRGB(255, 120, 120)
	label.TextStrokeColor3 = profile.TextStrokeColor or Color3.fromRGB(8, 8, 8)
	label.TextStrokeTransparency = profile.TextStrokeTransparency or 0
	label.ZIndex = profile.ZIndex or 120
	label.Parent = parent

	local endPos = profile.EndPosition or UDim2.fromScale(0.5, 0.1)
	local dur = profile.DurationSeconds or 0.42
	TweenService:Create(
		label,
		TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = endPos,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	):Play()

	task.delay(dur + 0.06, function()
		if label and label.Parent then
			label:Destroy()
		end
	end)
end

return DamageNumberView
