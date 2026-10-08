--[[ ============================================================================
    Neat XP Drops - entry point / event wiring.
    Creates the standalone bar and forwards game events to it.
    (No dependency on any other XP-drop mod.)
============================================================================ ]]--

NeatXPDrops = NeatXPDrops or {}
local bar = nil

local function onCreatePlayer(idx, player)
    if bar == nil then
        bar = NeatXPBar:new(idx, player)
        bar:initialise()
        bar:instantiate()
        bar:addToUIManager()
        NeatXPDrops.bar = bar
    elseif bar:getPlayerIsDead() then
        bar:setPlayer(idx, player)
    end
end

local function onPlayerDeath(player)
    if bar ~= nil and player == bar:getPlayer() then
        bar:setPlayerIsDead(true)
    end
end

local function onAddXP(player, perk, amount)
    if bar ~= nil and perk ~= nil and player == bar:getPlayer() then
        bar:onAddXP(perk, amount)
    end
end

local function onSave()
    if bar ~= nil then bar:writeConfig() end
end

Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnPlayerDeath.Add(onPlayerDeath)
Events.AddXP.Add(onAddXP)
Events.OnSave.Add(onSave)
