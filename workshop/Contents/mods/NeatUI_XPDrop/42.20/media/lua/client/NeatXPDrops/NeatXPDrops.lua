--[[ ============================================================================
    Neat XP Drops - entry point / event wiring.
    Creates the standalone bar and forwards game events to it.
    (No dependency on any other XP-drop mod.)

    Build 42.20: the bar detects XP by polling the character's own XP table
    (NeatXPBar:pollXP), because the engine only fires the AddXP Lua event when
    it is not a multiplayer client. Events.AddXP is therefore no longer wired
    up - doing both would double-count every drop in singleplayer.
============================================================================ ]]--

require "NeatXPDrops/NeatXPStyle"
require "NeatXPDrops/NeatXPSettings"

NeatXPDrops = NeatXPDrops or {}

local KEYBIND_SECTION = "[NeatUI XP Drop]"
local KEYBIND_CONFIG  = "Toggle XP Drop config"

local bar = nil

-- "Hide the mod completely" in Mod Options: the whole element leaves the UI
-- manager, so the collapsed "XP" pill disappears along with the panel.
local function applyVisibility()
    if bar == nil then return end
    if NeatXPSettings.isHidden() then
        if bar.configPanel and bar.configPanel.close then bar.configPanel:close() end
        if bar._menu and bar._menu.close then bar._menu:close() end
        bar:setVisible(false)
        bar:removeFromUIManager()
    else
        bar:setVisible(true)
        bar:addToUIManager()
    end
end

--- "Nascondi automaticamente", riportata addosso alla barra.
---
--- Va rifatta qui e non solo quando l'opzione cambia: le opzioni si applicano
--- su OnGameBoot, che scatta una volta per processo e **prima** che la barra
--- esista. Al primo avvio non se ne accorgeva nessuno perche' la si toccava a
--- mano; rientrando in partita la barra viene ricostruita da zero e nasceva
--- senza l'impostazione, finche' non si spegneva e riaccendeva l'opzione.
local function applyAutoHide()
    if bar == nil or not bar.setAutoHide then return end
    bar:setAutoHide(NeatXPSettings.isAutoHide())
end

local function onCreatePlayer(idx, player)
    if player == nil or not player:isLocalPlayer() then return end
    if bar == nil then
        bar = NeatXPBar:new(idx, player)
        bar:initialise()
        bar:instantiate()
        bar:addToUIManager()
        NeatXPDrops.bar = bar
    elseif bar:getPlayerIsDead() or bar:getPlayer() ~= player then
        bar:setPlayer(idx, player)
    end
    applyVisibility()
    applyAutoHide()

    -- Da qui e non da OnGameBoot: il singleton della radio e i nomi delle
    -- abilita' esistono solo a partita avviata. E' idempotente, e se ancora non
    -- c'e' niente da agganciare non lascia traccia e ci riprova al prossimo
    -- giro.
    NeatXPSettings.hookVanillaHalo()
end

local function onPlayerDeath(player)
    if bar ~= nil and player == bar:getPlayer() then
        bar:setPlayerIsDead(true)
    end
end

local function onSave()
    if bar ~= nil then bar:writeConfig() end
end

-- MP clients never get OnSave, so also flush on disconnect / game end.
local function onDisconnect()
    if bar ~= nil then bar:writeConfig() end
end

local function onKeyPressed(key)
    if bar == nil or NeatXPSettings.isHidden() then return end
    if getCore():isKey(KEYBIND_CONFIG, key) then
        bar:toggleConfig()
    end
end

local function initKeyBindings()
    table.insert(keyBinding, { value = KEYBIND_SECTION })
    table.insert(keyBinding, { value = KEYBIND_CONFIG, key = 0 })
end

--- La lettura degli XP, guidata da un evento e non dal pannello.
---
--- Stava dentro NeatXPBar:update, e un pannello fuori dall'UI manager non
--- riceve update: con l'autohide attivo la lettura si fermava proprio quando
--- serviva, e il pannello non sarebbe mai tornato a galla.
local function onTick()
    if bar == nil or NeatXPSettings.isHidden() then return end
    if bar.player_isDead then return end
    bar:pollXP()
end

Events.OnTick.Add(onTick)

NeatXPSettings.registerHiddenCallback(applyVisibility)

NeatXPSettings.registerAutoHideCallback(function(on)
    local bar = NeatXPDrops and NeatXPDrops.bar
    if bar and bar.setAutoHide then bar:setAutoHide(on) end
end)

Events.OnGameBoot.Add(initKeyBindings)
Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnPlayerDeath.Add(onPlayerDeath)
Events.OnSave.Add(onSave)
Events.OnDisconnect.Add(onDisconnect)
Events.OnKeyPressed.Add(onKeyPressed)
