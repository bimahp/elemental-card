-- TrainerInteraction: onboarding deck choice and post-onboarding trainer battles.
local Players=game:GetService("Players")
local ProximityPromptService=game:GetService("ProximityPromptService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local DialogueController=require(script.Parent.DialogueController)
local Remotes=ReplicatedStorage:WaitForChild("Remotes")
local localPlayer=Players.LocalPlayer
local Trainers=workspace:WaitForChild("Trainers",30)
local currentStage="complete"
local STARTER_DIALOGUES={
 ["Trainer Mighty"]={Segments={"Gronak here. Ruby Bears crush everything in their path.","Raw power and armor - that is the Mighty way. Grind them into dust.","Want my deck? It will teach you how to dominate the board."},Options={{Label="Yes - give me the Mighty deck!",Action="CHOOSE"},{Label="I will think about it.",Action="CLOSE"}}},
 ["Trainer Swift"]={Segments={"Ziri. I do not waste time - and neither do my cats.","Speed, combos, chain strikes. The Swift way hits before you blink.","I will give you my deck if you are serious."},Options={{Label="Yes - give me the Swift deck!",Action="CHOOSE"},{Label="I will think about it.",Action="CLOSE"}}},
 ["Trainer Vital"]={Segments={"Catherine. Sapphire Frogs endure everything you throw at them.","Healing, lifesteal, rebirth - we do not die easy. That is the Vital way.","Ready to learn patience? I can give you my deck."},Options={{Label="Yes - give me the Vital deck!",Action="CHOOSE"},{Label="I will think about it.",Action="CLOSE"}}},
}
local BATTLE_DIALOGUES={
 ["Trainer Mighty"]={Segments={"Hmph. Another challenger approaches the Ruby Bears.","My bears are armored and unyielding. Face them if you dare!"},Options={{Label="I accept your challenge!",Action="BATTLE"},{Label="Not right now.",Action="CLOSE"}}},
 ["Trainer Swift"]={Segments={"Oh? You noticed me. Most do not - until it is too late.","The Emerald Cats strike before you can blink. Ready?"},Options={{Label="Let us go!",Action="BATTLE"},{Label="Maybe later.",Action="CLOSE"}}},
 ["Trainer Vital"]={Segments={"Welcome, traveler. The Sapphire Frogs never stay down.","Can you outlast a tide that never stops healing?"},Options={{Label="I will try!",Action="BATTLE"},{Label="Not today.",Action="CLOSE"}}},
}
local CONFIRM_TEXT={
 ["Trainer Mighty"]="Are you sure you want to start with the Mighty deck?",
 ["Trainer Swift"]="Are you sure you want to start with the Swift deck?",
 ["Trainer Vital"]="Are you sure you want to start with the Vital deck?",
}
local function findTrainerModel(prompt)
 if not Trainers then return nil end
 local ancestor=prompt.Parent
 while ancestor and ancestor~=workspace do if ancestor.Parent==Trainers then return ancestor end;ancestor=ancestor.Parent end
end
local openStarterDialogue
local function openConfirm(model)
 DialogueController:Open(model,{Segments={CONFIRM_TEXT[model.Name] or "Are you sure?"},Options={{Label="Yes, I am sure!",Action="CONFIRM"},{Label="Actually, let me think.",Action="CANCEL"}}},function(action)
  if action=="CONFIRM" then Remotes.ChooseStarterDeck:FireServer(model.Name)
  elseif action=="CANCEL" and currentStage=="find_trainer" then openStarterDialogue(model) end
 end)
end
openStarterDialogue=function(model)
 local data=STARTER_DIALOGUES[model.Name];if not data then return end
 DialogueController:Open(model,data,function(action) if action=="CHOOSE" then openConfirm(model) end end)
end
local function openBattleDialogue(model)
 local data=BATTLE_DIALOGUES[model.Name];if not data then return end
 DialogueController:Open(model,data,function(action) if action=="BATTLE" then Remotes.StartTrainerBattle:FireServer(model.Name) end end)
end
local function applyQuestState(data)
 if type(data)~="table" then return end
 currentStage=data.stage or "complete"
 if currentStage~="find_trainer" and DialogueController.IsOpen then DialogueController:Close() end
end
ProximityPromptService.PromptTriggered:Connect(function(prompt,player)
 if player and player~=localPlayer then return end
 if DialogueController.IsOpen then return end
 local model=findTrainerModel(prompt);if not model then return end
 if currentStage=="find_trainer" then openStarterDialogue(model) elseif currentStage=="complete" then openBattleDialogue(model) end
end)
Remotes.QuestStateChanged.OnClientEvent:Connect(applyQuestState)
task.spawn(function()
 local snapshotRemote=Remotes:WaitForChild("GetQuestSnapshot",10);if not snapshotRemote then return end
 for _=1,20 do local ok,data=pcall(function() return snapshotRemote:InvokeServer() end);if ok and data then applyQuestState(data);return end;task.wait(0.5) end
 warn("[TrainerInteraction] quest snapshot unavailable")
end)
print("[TrainerInteraction] loaded")
