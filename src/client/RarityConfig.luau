local RarityConfig = {}

RarityConfig.PreviewColors = {
	Common = Color3.fromRGB(185, 185, 185),
	Uncommon = Color3.fromRGB(85, 220, 110),
	Rare = Color3.fromRGB(80, 150, 255),
	Legendary = Color3.fromRGB(255, 185, 55),
	Mythic = Color3.fromRGB(210, 95, 255),
	God = Color3.fromRGB(255, 70, 70),
	Transcendent = Color3.fromRGB(0, 0, 0),
}

RarityConfig.BorderPulseScale = {
	Common = 1,
	Uncommon = 1.08,
	Rare = 1.18,
	Legendary = 1.45,
	Mythic = 1.3,
	God = 1.62,
	Transcendent = 1.85,
}

function RarityConfig.GetPreviewRarityColor(rarity)
	return RarityConfig.PreviewColors[rarity] or RarityConfig.PreviewColors.Common
end

function RarityConfig.GetBorderPulseScale(rarity)
	return RarityConfig.BorderPulseScale[rarity] or RarityConfig.BorderPulseScale.Common
end

function RarityConfig.GetDefaultRarityBorderColorSequence()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.08, Color3.fromRGB(0, 255, 80)),
		ColorSequenceKeypoint.new(0.16, Color3.fromRGB(0, 200, 255)),
		ColorSequenceKeypoint.new(0.24, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(0.32, Color3.fromRGB(255, 80, 0)),
		ColorSequenceKeypoint.new(0.40, Color3.fromRGB(255, 0, 200)),
		ColorSequenceKeypoint.new(0.48, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.56, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(0.64, Color3.fromRGB(0, 255, 80)),
		ColorSequenceKeypoint.new(0.72, Color3.fromRGB(0, 200, 255)),
		ColorSequenceKeypoint.new(0.80, Color3.fromRGB(255, 0, 200)),
		ColorSequenceKeypoint.new(0.88, Color3.fromRGB(255, 80, 0)),
		ColorSequenceKeypoint.new(0.96, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
end

function RarityConfig.BuildBorderGradient(baseColor, rarity)
	if rarity == "God" then
		-- Gold gradient for God rarity
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 130, 40)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 215, 60)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 130, 40)),
		})
	end
	local bright = baseColor:Lerp(Color3.new(1, 1, 1), 0.35)
	local dark = baseColor:Lerp(Color3.new(0, 0, 0), 0.25)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, dark),
		ColorSequenceKeypoint.new(0.45, bright),
		ColorSequenceKeypoint.new(1, dark),
	})
end

return RarityConfig
