-- Shared hover/hold card preview. The static API remains for BattleUI;
-- new() creates isolated instances for non-battle surfaces such as Vending.
local CardPreviewController = {}
local Preview = {}
Preview.__index = Preview

local DEFAULT_SCALE = 1.7
local GAP = 10
local defaultPreview

local function createLayer(host, name, zIndex)
	local layer = host:FindFirstChild(name)
	local ownsLayer = false
	if not layer then
		layer = Instance.new("Frame")
		layer.Name = name
		layer.BackgroundTransparency = 1
		layer.Size = UDim2.fromScale(1, 1)
		layer.ZIndex = zIndex
		layer.Active = false
		layer.Parent = host
		ownsLayer = true
	end
	return layer, ownsLayer
end

function CardPreviewController.new(ctx)
	assert(ctx and ctx.CardVisuals, "CardPreviewController.new requires CardVisuals")
	local host = ctx.host or (ctx.main and ctx.main.Parent)
	assert(host, "CardPreviewController.new requires host or main")

	local layer, ownsLayer = createLayer(host, ctx.layerName or "PreviewLayer", ctx.zIndex or 50)
	local self = setmetatable({
		CardVisuals = ctx.CardVisuals,
		previewLayer = layer,
		ownsLayer = ownsLayer,
		previewScale = ctx.previewScale or DEFAULT_SCALE,
		current = nil,
	}, Preview)
	self:setCardSize(ctx.HW, ctx.HH)
	return self
end

function Preview:setCardSize(width, height)
	assert(width and height, "preview card size is required")
	self.previewW = width * self.previewScale
	self.previewH = height * self.previewScale
end

function Preview:hide()
	if self.current then
		self.current:Destroy()
		self.current = nil
	end
end

function Preview:show(sourceFrame, opts, side)
	self:hide()

	local CardVisuals = self.CardVisuals
	local previewW, previewH = self.previewW, self.previewH
	local f = CardVisuals.buildCardFrame(previewW, previewH, "full")
	f.Name = "PreviewCard"
	local stk = f:FindFirstChildOfClass("UIStroke")
	if stk then
		stk.Thickness = 4
		stk.Color = CardVisuals.TC_type[opts.battleType] or CardVisuals.TC_type.NEUTRAL
	end
	CardVisuals.updateCardFrame(f, opts)

	local srcPos, srcSize = sourceFrame.AbsolutePosition, sourceFrame.AbsoluteSize
	local layerPos, layerSize = self.previewLayer.AbsolutePosition, self.previewLayer.AbsoluteSize
	local visMinX = math.max(0, -layerPos.X)
	local visMinY = math.max(0, -layerPos.Y)
	local maxX = math.max(visMinX, layerSize.X - previewW)
	local maxY = math.max(visMinY, layerSize.Y - previewH)

	local sourceLeft = srcPos.X - layerPos.X
	local sourceRight = srcPos.X + srcSize.X - layerPos.X
	local x, y
	if side == "left" or side == "right" then
		y = (srcPos.Y + srcSize.Y / 2 - layerPos.Y) - previewH / 2
		local leftX = sourceLeft - previewW - GAP
		local rightX = sourceRight + GAP
		if side == "right" then
			x = rightX <= maxX and rightX or leftX
		else
			x = leftX >= visMinX and leftX or rightX
		end
	else
		x = (srcPos.X + srcSize.X / 2) - layerPos.X - previewW / 2
		y = sourceFrame.AbsolutePosition.Y - layerPos.Y - previewH - GAP
	end

	x = math.clamp(x, visMinX, maxX)
	y = math.clamp(y, visMinY, maxY)
	f.Position = UDim2.fromOffset(x, y)
	f.Parent = self.previewLayer
	self.current = f
end

function Preview:destroy()
	self:hide()
	if self.ownsLayer and self.previewLayer then self.previewLayer:Destroy() end
	self.previewLayer = nil
end

function CardPreviewController.init(ctx)
	if defaultPreview then defaultPreview:destroy() end
	defaultPreview = CardPreviewController.new(ctx)
end

function CardPreviewController.show(sourceFrame, opts, side)
	assert(defaultPreview, "CardPreviewController.init must be called before show")
	defaultPreview:show(sourceFrame, opts, side)
end

function CardPreviewController.hide()
	if defaultPreview then defaultPreview:hide() end
end

return CardPreviewController
