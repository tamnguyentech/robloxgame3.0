-- RainbowBorderStroke.luau
-- Animated rainbow outline for UIStroke (white base + UIGradient, fast rotation).
-- Matches shop concept tiles; use for Rainbow border tier cards everywhere.

local RunService = game:GetService("RunService")

local GRADIENT_NAME = "RainbowTierStrokeGradient"

local RainbowBorderStroke = {}

local connections: { [Instance]: RBXScriptConnection } = {}

function RainbowBorderStroke.createRainbowColorSequence()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 90, 120)),
		ColorSequenceKeypoint.new(0.15, Color3.fromRGB(255, 200, 80)),
		ColorSequenceKeypoint.new(0.30, Color3.fromRGB(220, 255, 110)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(80, 230, 255)),
		ColorSequenceKeypoint.new(0.60, Color3.fromRGB(120, 150, 255)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(220, 120, 255)),
		ColorSequenceKeypoint.new(0.90, Color3.fromRGB(255, 100, 200)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 90, 120)),
	})
end

--- Stop animation and remove the rainbow gradient from this stroke (idempotent).
function RainbowBorderStroke.detach(uiStroke)
	if not (uiStroke and uiStroke.Parent) then
		return
	end
	local conn = connections[uiStroke]
	if conn then
		conn:Disconnect()
		connections[uiStroke] = nil
	end
	local grad = uiStroke:FindFirstChild(GRADIENT_NAME)
	if grad then
		grad:Destroy()
	end
end

--- Apply rainbow gradient + rotation. Caller should remove conflicting UIGradients (e.g. CardBorderGradient) first if needed.
function RainbowBorderStroke.attach(uiStroke, rotationDegPerSec)
	if not (uiStroke and uiStroke.Parent) then
		return
	end
	RainbowBorderStroke.detach(uiStroke)

	uiStroke.Color = Color3.new(1, 1, 1)

	local strokeGrad = Instance.new("UIGradient")
	strokeGrad.Name = GRADIENT_NAME
	strokeGrad.Color = RainbowBorderStroke.createRainbowColorSequence()
	strokeGrad.Rotation = 0
	strokeGrad.Parent = uiStroke

	local speed = rotationDegPerSec or 135
	local conn = RunService.RenderStepped:Connect(function(dt)
		if not (strokeGrad.Parent and uiStroke.Parent) then
			RainbowBorderStroke.detach(uiStroke)
			return
		end
		strokeGrad.Rotation = (strokeGrad.Rotation + dt * speed) % 360
	end)
	connections[uiStroke] = conn
end

return RainbowBorderStroke
