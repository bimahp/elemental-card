-- Headless checks for PanelCoordinator (PLAN_UI_FOUNDATIONS step 5).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Coordinator = require(ReplicatedStorage.Modules.PanelCoordinator)

local Spec = {}

-- A fake panel that records what the coordinator asked of it.
local function panel(id: string, opts)
	opts = opts or {}
	local p = { open = false, closes = 0, backs = 0, refuse = false, pages = opts.pages or 1 }
	function p.close()
		if p.refuse then
			return false
		end
		p.open = false
		p.closes += 1
		Coordinator.release(id)
		return nil
	end
	function p.show()
		if Coordinator.claim(id) then
			p.open = true
		end
		return p.open
	end
	local handlers: any = { close = p.close, backdrop = opts.backdrop }
	if opts.pages then
		function handlers.back()
			p.backs += 1
			if p.pages <= 1 then
				p.close()
			else
				p.pages -= 1
			end
		end
	end
	Coordinator.register(id, handlers)
	return p
end

function Spec.run()
	Coordinator._reset()
	local library = panel("CardLibrary", { pages = 3 })
	local mall = panel("ItemMall")
	local vending = panel("VendingMachine")

	assert(library.show() and Coordinator.current() == "CardLibrary", "claiming opens the first panel")
	assert(mall.show() and not library.open and library.closes == 1, "claiming B closes A")
	assert(Coordinator.current() == "ItemMall", "B holds the claim")

	Coordinator.release("CardLibrary")
	assert(Coordinator.current() == "ItemMall", "a release by a panel without the claim is ignored")

	assert(Coordinator.back() and not mall.open and Coordinator.current() == nil, "back closes a panel without pages")
	assert(Coordinator.back() == false, "back with nothing open does nothing")

	assert(library.show(), "the library opens again")
	Coordinator.back()
	Coordinator.back()
	assert(library.open and library.backs == 2 and library.pages == 1, "back steps through pages first")
	Coordinator.back()
	assert(not library.open and Coordinator.current() == nil, "back on the root page closes the panel")

	vending.show()
	vending.refuse = true
	assert(not mall.show() and not mall.open, "a panel that refuses to close keeps the claim")
	assert(vending.open and Coordinator.current() == "VendingMachine", "the refusing panel stays open")
	vending.refuse = false
	assert(mall.show() and not vending.open, "once it allows it, the claim moves")

	Coordinator.closeAll()
	assert(not mall.open and Coordinator.current() == nil, "closeAll closes the open panel")
	assert(not pcall(Coordinator.claim, "Unknown"), "claiming an unregistered panel errors")

	-- The shared backdrop follows the open panel.
	local realSetBackdrop = Coordinator._setBackdrop
	local backdrop = false
	Coordinator._setBackdrop = function(on)
		backdrop = on
	end
	local matchmaking = panel("Matchmaking", { backdrop = true })
	assert(matchmaking.show() and backdrop, "a backdrop panel turns the backdrop on")
	assert(mall.show() and not backdrop, "switching to a panel without one turns it off")
	assert(matchmaking.show() and backdrop, "and back on")
	matchmaking.close()
	assert(not backdrop and Coordinator.current() == nil, "closing the panel turns the backdrop off")
	Coordinator._setBackdrop = realSetBackdrop

	Coordinator._reset()
	return "PanelCoordinatorSpec: all checks passed"
end

return Spec
