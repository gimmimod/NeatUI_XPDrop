--[[ ============================================================================
    NeatXPBar - standalone XP-drops bar (NeatUI themed).

    Build 42.20 notes
    -----------------
    * XP detection is done by polling IsoGameCharacter.XP:getXP(perk) instead of
      listening to Events.AddXP. In B42 the engine only fires the AddXP Lua event
      when it is NOT a multiplayer client (IsoGameCharacter$XP.AddXP ends with
      "if (!GameClient.client) triggerEvent(...)"), so on a server the bar never
      saw a single drop and stayed frozen on whatever skill it started with -
      Cooking, because that is the first perk with a parent in the Perks index
      order (None, Agility, Cooking, ...). Polling the character's own XP map
      works in singleplayer, in splitscreen and on MP clients alike, and it also
      reports the real applied amount rather than the pre-multiplier value.
    * Perks are grouped by their parent category (Combat / Firearm / Crafting /
      Survivalist / Physical / Farming), matching how B42 lays skills out.

    Layout / sizing
    ---------------
    Every metric derives from a single `scale` factor, driven by the corner grip
    in the bottom-right (framework ResizeIcon art, positioned the way Rocco's
    resizable panels do it: an ISResizeWidget at `w - size, h - size`). Only the
    width it reports is used - height follows from the scale - so dragging it
    behaves as a width handle. The progress bar stops `barRightReserve` short of
    the right edge to leave the grip its corner; the header sits above the grip
    and needs no inset.

    The XP readout is centred inside the progress bar rather than sitting on its
    own line above it - one row shorter, and no dead space to the left of the
    right-aligned numbers.
============================================================================ ]]--

require "ISUI/ISPanel"
require "ISUI/ISResizeWidget"
require "NeatXPDrops/NeatXPStyle"

NeatXPBar = ISPanel:derive("NeatXPBar")

local DEFAULT_OFF = { Fitness = true, Strength = true, Lightfoot = true, Sneak = true, Maintenance = true }

-- Category order for the skill list / config grid. Any category the game adds
-- later (or a mod adds through media/perks.txt) is appended after these.
local CATEGORY_ORDER = { "Combat", "Firearm", "Crafting", "Survivalist", "PhysicalCategory", "FarmingCategory" }

-- Smallest XP delta worth showing: guards against float noise in the poll.
local XP_EPSILON = 0.001

local MIN_SCALE = 0.75
local MAX_SCALE = 3.00

local function round(v) return math.floor(v + 0.5) end

function NeatXPBar:new(playerIndex, player)
    local fontSize = getCore():getOptionFontSize()
    local w = 190 + (14 * (fontSize - 1))

    local o = ISPanel:new(getCore():getScreenWidth() - 360, 180, w, 60)
    setmetatable(o, self)
    self.__index = self

    o.playerIndex = playerIndex
    o.player = player
    o.player_isDead = false

    o.baseWidth = w
    o.baseFontH = getTextManager():getFontHeight(UIFont.Small)
    o.scale = 1.0

    o.moveWithMouse = true
    o.background = false

    o.tracked = {}
    o.expTables = {}
    o.perkIndices = {}
    o.perkObjects = {}
    o.skillOrder = {}
    o.categories = {}

    o.currentSkill = nil
    o.currentName = ""

    o.drops = {}
    -- Gli avvisi che prendono il posto del testo XP di radio e TV: freccia,
    -- icona e nome dell'abilita', sopra la testa dov'era quello del gioco.
    o.halos = {}
    -- Le abilita' scese di una riga quando i pannelli impilati sono accesi.
    -- Sempre una tabella, anche a opzione spenta: chi la scorre non deve
    -- chiedersi se esiste.
    o.extraRows = {}
    o.tooltipVisible = false
    o.collapsed = false
    o.locked = false

    o.xpSnapshot = nil          -- perk id -> total XP at the last poll
    o.configPanel = nil

    o:computeMetrics()
    return o
end

function NeatXPBar:initialise()
    ISPanel.initialise(self)
    self:buildSkillData()
    self:readConfig()
    self:refreshSnapshot()
end

function NeatXPBar:createChildren()
    ISPanel.createChildren(self)
    self:createResizeWidget()
    self:layout()
end

-- =============================================================================
-- Sizing
-- =============================================================================

-- All metrics for the current scale. Fonts come from the framework ladder so a
-- big panel gets a bigger face instead of the same tiny one floating in space.
function NeatXPBar:computeMetrics()
    local s = self.scale
    local targetTextH = self.baseFontH * s

    self.font, self.fontH = NeatXPStyle.pickFont(targetTextH)
    local dropFactor = (NeatXPSettings and NeatXPSettings.dropSizeFactor)
        and NeatXPSettings.dropSizeFactor() or 1.55
    self.dropFont, self.dropFontH = NeatXPStyle.pickFont(targetTextH * dropFactor)

    self.pad      = math.max(4, round(6 * s))
    self.headerH  = math.max(round(22 * s), self.fontH + round(8 * s))
    self.iconSize = math.max(16, self.headerH - round(6 * s))
    self.barH     = self.fontH + round(6 * s)
    self.gap      = math.max(2, round(3 * s))

    -- 16 fissi come NR_ResizeWidget.SIZE di Rocco: il grip non scala con il
    -- pannello, altrimenti su una finestra grande diventa sproporzionato.
    self.gripSize = 16

    self.contentW = round(self.baseWidth * s)
    self.contentH = self.headerH + self.gap + self.barH + self.pad

    -- The grip owns the bottom-right corner, so the bar stops short of it.
    -- The header is clear of it: the grip never reaches above headerH.
    self.barRightReserve = self.gripSize + math.max(2, round(2 * s))

    self.pillW = round((self.fontH * 2 + 16) * s)
    self.pillH = self.fontH + round(10 * s)
end

function NeatXPBar:setScale(s)
    s = math.max(MIN_SCALE, math.min(s or 1, MAX_SCALE))
    if math.abs(s - self.scale) < 0.0005 then return end
    self.scale = s
    self:computeMetrics()
    self:layout()
end

function NeatXPBar:layout()
    if self.collapsed then
        self:setWidth(self.pillW)
        self:setHeight(self.pillH)
    else
        self:setWidth(self.contentW)
        self:setHeight(self.contentH)
    end
    self:positionResizeWidget()
    self:clampToScreen()
end

function NeatXPBar:createResizeWidget()
    local sz = self.gripSize
    local widget = ISResizeWidget:new(0, 0, sz, sz, self)
    widget.anchorRight  = false
    widget.anchorBottom = false
    widget:initialise()
    widget.prerender = function(wdg)
        NeatXPStyle.drawResizeGrip(wdg, 0, 0, wdg.width, wdg.mouseOver or wdg.resizing)
    end
    widget.render = function() end
    widget.resizeFunction = function(target, w, _h) target:onGripResize(w) end

    -- The widget takes mouse capture for the whole drag, so the bar's own
    -- onMouseUp never fires: flush the new scale from here instead.
    local bar = self
    local upFns = { "onMouseUp", "onMouseUpOutside" }
    for _, name in ipairs(upFns) do
        local base = ISResizeWidget[name]
        widget[name] = function(wdg, x, y)
            local r = base(wdg, x, y)
            bar:writeConfig()
            return r
        end
    end

    ISPanel.addChild(self, widget)
    widget:setAlwaysOnTop(true)
    self.resizeWidget = widget
end

function NeatXPBar:positionResizeWidget()
    local wdg = self.resizeWidget
    if wdg == nil then return end
    local show = not self.collapsed and not self.locked
    wdg:setVisible(show)
    if not show then return end
    wdg:setWidth(self.gripSize)
    wdg:setHeight(self.gripSize)
    wdg:setX(self.contentW - self.gripSize)
    wdg:setY(self.contentH - self.gripSize)
    -- ISResizeWidget clamps against these; without a width the widget resets
    -- minimumHeight to 0 and lets the panel collapse to nothing.
    self.minimumWidth  = round(self.baseWidth * MIN_SCALE)
    self.minimumHeight = 0
end

function NeatXPBar:onGripResize(w)
    if self.locked or self.collapsed then return end
    self:setScale(w / self.baseWidth)
end

-- =============================================================================
-- Skill data
-- =============================================================================

-- A perk is a real skill when it has a parent; parent-less entries (Combat,
-- Crafting, Agility, None, MAX, ...) are the categories themselves.
function NeatXPBar:buildSkillData()
    local byCategory = {}
    local catOrder = {}

    for i = 1, Perks.getMaxIndex() do
        local perk = PerkFactory.getPerk(Perks.fromIndex(i - 1))
        local parent = perk and perk:getParent()
        if perk and parent and parent ~= Perks.None then
            local t = tostring(perk:getType())
            local catId = tostring(parent)

            self.perkIndices[t] = i - 1
            self.perkObjects[t] = perk   -- cached: the poller touches every perk each frame
            self.expTables[t] = {
                tonumber(perk:getXp1()), tonumber(perk:getXp2()), tonumber(perk:getXp3()),
                tonumber(perk:getXp4()), tonumber(perk:getXp5()), tonumber(perk:getXp6()),
                tonumber(perk:getXp7()), tonumber(perk:getXp8()), tonumber(perk:getXp9()),
                tonumber(perk:getXp10()),
            }
            if self.tracked[t] == nil then
                self.tracked[t] = not DEFAULT_OFF[t]
            end

            if byCategory[catId] == nil then
                byCategory[catId] = { id = catId, name = parent:getName(), skills = {} }
                table.insert(catOrder, catId)
            end
            table.insert(byCategory[catId].skills, t)
        end
    end

    -- Known categories first, in the vanilla display order, then anything new.
    local emitted = {}
    for _, catId in ipairs(CATEGORY_ORDER) do
        if byCategory[catId] then
            table.insert(self.categories, byCategory[catId])
            emitted[catId] = true
        end
    end
    for _, catId in ipairs(catOrder) do
        if not emitted[catId] then table.insert(self.categories, byCategory[catId]) end
    end

    for _, cat in ipairs(self.categories) do
        for _, skill in ipairs(cat.skills) do
            table.insert(self.skillOrder, skill)
        end
    end

    if self.currentSkill == nil and self.skillOrder[1] then
        self:setSkill(self.skillOrder[1])
    end
end

function NeatXPBar:getPerk(skillType)
    local perk = self.perkObjects[skillType]
    if perk ~= nil then return perk end
    local idx = self.perkIndices[skillType]
    if idx == nil then return nil end
    return PerkFactory.getPerk(Perks.fromIndex(idx))
end

function NeatXPBar:isTracked(skillType)
    if self.tracked[skillType] ~= nil then return self.tracked[skillType] end
    return true
end

function NeatXPBar:setTracked(skillType, v) self.tracked[skillType] = v end

function NeatXPBar:cleanExp(expTable, level, exp)
    for i = 1, level do exp = exp - (expTable[i] or 0) end
    return exp
end

function NeatXPBar:getExpMax(skillType, level)
    local t = self.expTables[skillType]
    if not t then return 1 end
    level = math.max(0, math.min(level + 1, 10))
    return t[level] or 1
end

function NeatXPBar:getExpCurrent(skillType, level, exp)
    local t = self.expTables[skillType]
    if not t then return 0 end
    level = math.max(0, math.min(level, 10))
    return self:cleanExp(t, level, exp)
end

function NeatXPBar:setSkill(skillType)
    local perk = self:getPerk(skillType)
    if perk then
        self.currentSkill = skillType
        self.currentName = perk:getName()
        -- Serve solo a pannelli impilati, per sapere quale riga e' la piu'
        -- silenziosa quando ne va sfrattata una.
        self.currentLastMs = getTimestampMs()

        -- Se quell'abilita' era in coda, adesso e' in cima: toglierla di li' o
        -- comparirebbe due volte, e il suo numero non saprebbe dove salire.
        for i = #self.extraRows, 1, -1 do
            if self.extraRows[i].skill == skillType then table.remove(self.extraRows, i) end
        end
    end
end

-- =============================================================================
-- XP polling (multiplayer-safe; see the header note)
-- =============================================================================

function NeatXPBar:getXPTable()
    local player = self.player
    if player == nil then return nil end
    local ok, xp = pcall(function() return player:getXp() end)
    if not ok then return nil end
    return xp
end

-- Re-read every tracked perk without emitting drops. Called on startup and
-- whenever the character behind the bar changes.
function NeatXPBar:refreshSnapshot()
    local xp = self:getXPTable()
    self.xpSnapshot = {}
    if xp == nil then return end
    for _, skillType in ipairs(self.skillOrder) do
        local perk = self:getPerk(skillType)
        if perk then
            self.xpSnapshot[skillType] = xp:getXP(perk) or 0
        end
    end
end

function NeatXPBar:pollXP()
    local xp = self:getXPTable()
    if xp == nil then return end
    if self.xpSnapshot == nil then self:refreshSnapshot(); return end

    for _, skillType in ipairs(self.skillOrder) do
        local perk = self:getPerk(skillType)
        if perk then
            local total = xp:getXP(perk) or 0
            local prev = self.xpSnapshot[skillType]
            if prev == nil then
                self.xpSnapshot[skillType] = total
            elseif total > prev + XP_EPSILON then
                self.xpSnapshot[skillType] = total
                self:onXPGained(skillType, perk, total - prev)
            elseif total < prev then
                -- XP was reset or reduced (respec mods, debug menu): resync only.
                self.xpSnapshot[skillType] = total
            end
        end
    end
end

--- Quanto resta a vista dopo l'ultimo XP, in millisecondi.
local AUTO_HIDE_MS = 5000

--- Con "nascondi automaticamente" attivo il pannello non c'e'. Questo lo fa
--- ricomparire e fa ripartire il conto alla rovescia.
function NeatXPBar:wakeForXP()
    if not self.autoHide then return end
    self.autoHideUntil = getTimestampMs() + AUTO_HIDE_MS
    if not self:isVisible() then
        self:setVisible(true)
        self:addToUIManager()
    end
end

function NeatXPBar:setAutoHide(v)
    self.autoHide = v and true or false
    if self.autoHide then
        -- Si sparisce subito: aspettare il primo XP per nascondersi vorrebbe
        -- dire lasciare il pannello li' finche' non si guadagna qualcosa.
        self.autoHideUntil = nil
    elseif not self:isVisible() then
        self:setVisible(true)
        self:addToUIManager()
    end
end

--- Vero quando l'autohide dice che adesso non si deve vedere.
function NeatXPBar:autoHidden()
    if not self.autoHide then return false end
    return not self.autoHideUntil or getTimestampMs() > self.autoHideUntil
end

-- Separazione minima fra due drop, in frazioni di vita: sotto questa soglia il
-- nuovo si mette in coda invece di partire subito.
local DROP_STAGGER = 0.28

-- Quanto puo crescere la coda. Oltre, si accetta la sovrapposizione: meglio due
-- numeri vicini che un numero che compare due secondi dopo il fatto.
local DROP_MAX_QUEUE = 0.85

--[[ I pannelli in piu'.

    Con l'opzione accesa, un'abilita' diversa da quella mostrata non scavalca la
    prima: quella che c'era scende di una riga e la nuova prende il posto in
    cima. Fino a tre in tutto, cioe' due in piu' del solito.

    Sono disegnati **fuori** dall'elemento, sotto di lui, e non ricevono clic.
    E' voluto: l'elemento resta alto una riga sola, quindi trascinamento,
    ridimensionamento, aggancio ai bordi, finestra di configurazione e pastiglia
    ripiegata continuano a lavorare esattamente come prima. Disegnare oltre i
    propri bordi qui e' gia' la norma - i drop lo fanno da sempre, sopra il
    pannello.

    Ogni riga ha i suoi drop, e ogni riga li fa salire soltanto dentro lo spazio
    che la separa da quella sopra: cosi' due numeri di due abilita' diverse non
    si incrociano mai, senza bisogno di ritagli.
]]
local STACK_MAX_EXTRA = 2       -- tre pannelli in tutto
local STACK_QUIET_MS = 6000     -- silenzio dopo il quale una riga in piu' se ne va

--- Dove mettere un'abilita' che ha appena preso XP, a pannelli impilati.
---
--- **Le righe stanno ferme.** Un'abilita' gia' a schermo resta dov'e' e si
--- limita a rinfrescare il proprio orologio: e' questo che permette a ogni
--- pannello di avere i suoi numeri, perche' un'abilita' che continua a
--- guadagnare non viene piu' strappata dalla sua riga per essere rimessa in
--- cima. Una nuova prende il primo posto libero sotto; se non ce n'e', prende
--- quello della piu' silenziosa - che puo' essere anche il pannello in cima.
---
--- I drop restano in un'unica lista e al momento di disegnarli ciascuno cerca
--- la riga che mostra la sua abilita': un numero segue il suo pannello, e non
--- c'e' una seconda lista da tenere allineata.
---@return boolean vero se l'abilita' e' finita sul pannello in cima
function NeatXPBar:placeSkill(skillType, name)
    if skillType == nil then return false end
    local now = getTimestampMs()

    -- Il primo XP della partita: il pannello in cima e' vuoto, e va riempito
    -- lui, non una riga sotto.
    if self.currentSkill == nil or skillType == self.currentSkill then
        self.currentLastMs = now
        return true
    end

    for _, r in ipairs(self.extraRows) do
        if r.skill == skillType then
            r.lastMs = now
            return false
        end
    end

    -- Il pannello in cima zitto da un po' cede il posto alla nuova. Senza,
    -- un'abilita' presa una volta all'inizio della partita restava in cima per
    -- sempre mentre le altre si mettevano sotto (segnalazione: Mira a 0, fissa).
    if now - (self.currentLastMs or 0) > STACK_QUIET_MS then
        self.currentLastMs = now
        return true
    end

    if #self.extraRows < STACK_MAX_EXTRA then
        table.insert(self.extraRows, { skill = skillType, name = name, lastMs = now })
        return false
    end

    -- Tutto pieno: si sfratta la piu' vecchia. Il pannello in cima partecipa,
    -- altrimenti un'abilita' presa una volta all'inizio resterebbe li' per
    -- sempre a occupare il posto migliore.
    local oldestIdx, oldestMs = nil, self.currentLastMs or 0
    for i, r in ipairs(self.extraRows) do
        if r.lastMs < oldestMs then oldestIdx, oldestMs = i, r.lastMs end
    end

    if oldestIdx then
        self.extraRows[oldestIdx] = { skill = skillType, name = name, lastMs = now }
        return false
    end

    self.currentLastMs = now
    return true
end

function NeatXPBar:onXPGained(skillType, perk, amount)
    -- Le abilita' non seguite non svegliano niente: e' la stessa riga che
    -- decide cosa mostrare, quindi "solo con le abilita' attivate" viene
    -- gratis, senza un secondo controllo che potrebbe divergere.
    if not self:isTracked(skillType) then return end

    -- Prima del controllo su collapsed: in autohide il pannello e' proprio
    -- nascosto, e uscendo qui non tornerebbe mai.
    self:wakeForXP()

    if NeatXPSettings.isStackPanels() then
        -- A pannelli impilati il pannello in cima **non** insegue l'ultima
        -- abilita': ognuna ha la sua riga e ci resta. setSkill si chiama solo
        -- quando la nuova finisce davvero in cima.
        if self:placeSkill(skillType, perk:getName()) or self.currentSkill == nil then
            self:setSkill(skillType)
        end
    else
        if #self.extraRows > 0 then
            -- Opzione spenta a pannelli aperti: si sgombra subito, o
            -- resterebbero disegnati sotto per sempre.
            self.extraRows = {}
        end
        self:setSkill(skillType)
    end

    -- A pannello ripiegato di norma non si accoda niente: i numeri salirebbero
    -- da una pastiglia larga due dita. Con i numeri sopra il personaggio pero'
    -- il pannello non c'entra piu' nulla, e devono continuare a comparire.
    if self.collapsed and not NeatXPSettings.isDropOverPlayer() then return end

    local last = self.drops[#self.drops]
    if last and last.skill == skillType and last.age < 0.15 then
        last.amount = last.amount + amount
        return
    end

    -- Due XP a distanza di un soffio si sovrapponevano. Il nuovo parte con
    -- un'eta' **negativa**: e' in coda, e comincia a salire quando il
    -- precedente si e' gia' mosso abbastanza.
    --
    -- Il tetto e' la parte "intelligente": oltre quello non si accoda piu' e si
    -- accetta la sovrapposizione. Senza, una raffica di dieci XP metterebbe in
    -- fila dieci ritardi e l'ultimo comparirebbe secondi dopo il fatto, che e'
    -- peggio del problema che si voleva risolvere.
    local age = 0
    if last and last.age < DROP_STAGGER then
        age = math.max(last.age - DROP_STAGGER, -DROP_MAX_QUEUE)
    end

    table.insert(self.drops, { skill = skillType, name = perk:getName(), amount = amount, age = age })
end

--[[ L'avviso che prende il posto del testo XP di radio e TV.

    Arriva dal gancio su `ISRadioInteractions.addHalo`, che ci passa il **nome**
    dell'abilita' - e' l'unica cosa che quella funzione riceve. Il tipo, che
    serve per l'icona, si ritrova cercando fra i perk: la mappa si costruisce
    una volta sola.

    Non passa dalle abilita' seguite: il gioco aveva deciso di dirtelo, e noi
    stiamo sostituendo il suo avviso, non aggiungendone uno nostro. Filtrarlo
    vorrebbe dire far sparire una notizia che senza la mod avresti avuto.
]]
local HALO_LIFETIME = 2.2

function NeatXPBar:skillTypeByName(name)
    if self._typeByName == nil then
        self._typeByName = {}
        for _, t in ipairs(self.skillOrder) do
            local perk = self:getPerk(t)
            if perk then
                local n = perk:getName()
                if n and n ~= "" then self._typeByName[n] = t end
            end
        end
    end
    return self._typeByName[name]
end

--- Un avviso sopra la testa al posto di quello del gioco.
---
--- `up` nil vuol dire senza freccia - il gioco stesso non ne mette una quando
--- non c'e' un numero. `withIcon` chiede l'icona dell'abilita': la si aggiunge
--- solo se il testo e' davvero il nome di una, perche' per la noia un'icona non
--- esiste e inventarla sarebbe peggio del niente.
function NeatXPBar:addHalo(name, up, good, withIcon)
    if type(name) ~= "string" or name == "" then return end

    -- Se il pannello era nascosto va risvegliato, o l'avviso non verrebbe
    -- disegnato da nessuno: e' questo elemento a disegnarlo.
    self:wakeForXP()

    -- Lo stesso avviso due volte in un soffio: il gioco a volte lo fa, e due
    -- righe identiche sovrapposte si leggono peggio di una.
    local last = self.halos[#self.halos]
    if last and last.name == name and last.age < 0.2 then return end

    self.halos[#self.halos + 1] = {
        name  = name,
        skill = withIcon and self:skillTypeByName(name) or nil,
        icon  = withIcon == true,
        up    = up,
        good  = good ~= false,
        age   = 0,
    }
end

--- La forma di prima, tenuta perche' la chiamava qualcun altro: un'abilita' che
--- guadagna XP e' una freccia in su e una buona notizia, con la sua icona.
function NeatXPBar:addSkillHalo(name)
    self:addHalo(name, true, true, true)
end

-- Kept for compatibility with anything that used to call into the bar directly.
function NeatXPBar:onAddXP(perk, amount)
    if perk == nil or amount == nil or amount == 0 then return end
    local skillType = tostring(perk:getType())
    if self.perkIndices[skillType] == nil then return end
    self:onXPGained(skillType, perk, amount)
end

local DROP_LIFETIME = 1.0   -- seconds a drop stays on screen (frame-rate independent)

function NeatXPBar:update()
    ISPanel.update(self)

    -- Scaduto il tempo dall'ultimo XP il pannello si toglie di mezzo. Non
    -- basta smettere di disegnarlo: resterebbe li' a intercettare i clic.
    if self:autoHidden() and self:isVisible() then
        self:setVisible(false)
        self:removeFromUIManager()
    end

    -- Gli XP **non** si leggono piu' qui: vedi NeatXPBar:tick. Un pannello
    -- tolto dall'UI manager non riceve piu' update, quindi con l'autohide
    -- attivo la lettura si fermava e il pannello non tornava mai - che e'
    -- esattamente il sintomo segnalato.

    local now = getTimestampMs()

    -- Le righe in piu' se ne vanno da sole dopo un po' di silenzio: sono un
    -- avviso, non un secondo pannello permanente.
    --
    -- **Si sfilano solo dall'ultima, e ci si ferma alla prima ancora viva.**
    -- Togliendo una riga di mezzo, quelle dopo scalerebbero di un posto: un
    -- pannello che scivola su di uno scalino mentre lo stai guardando, senza
    -- che sia successo niente a quell'abilita'. Una riga zitta in mezzo a due
    -- vive resta dov'e' finche' non tocca a lei essere l'ultima - oppure finche'
    -- placeSkill non la riusa per un'abilita' nuova, che avviene sul posto e non
    -- muove niente.
    while #self.extraRows > 0
        and now - self.extraRows[#self.extraRows].lastMs > STACK_QUIET_MS do
        table.remove(self.extraRows)
    end

    -- La cima e' zitta e sotto c'e' chi lavora: sale la riga attiva piu'
    -- recente. Le righe dopo di lei salgono di un posto - e' l'unico caso in
    -- cui si accetta, perche' una cima ferma su un'abilita' che non guadagna
    -- piu' niente e' peggio di uno scalino.
    if NeatXPSettings.isStackPanels() and #self.extraRows > 0
        and now - (self.currentLastMs or 0) > STACK_QUIET_MS then
        local best, bestMs = 1, -1
        for i, r in ipairs(self.extraRows) do
            if r.lastMs > bestMs then best, bestMs = i, r.lastMs end
        end
        local r = table.remove(self.extraRows, best)
        self:setSkill(r.skill)
        self.currentLastMs = r.lastMs
    end
end

--[[ L'eta' di numeri e avvisi avanza qui, non in update.

    update gira al passo della logica di gioco, non a quello dello schermo: i
    numeri avanzavano a scalini e a 60 fotogrammi si vedevano salire a scatti,
    "come a 10 fps" nella segnalazione. Il disegno invece passa a ogni
    fotogramma, quindi l'eta' si aggiorna dove la si usa, sull'orologio vero:
    un numero e' sempre dove deve essere in quell'istante, a qualunque frequenza.

    Il tetto a 0.1 s resta: dopo una pausa lunga (menu, caricamento) un numero
    riprende da dove era invece di sparire in un colpo.
]]
function NeatXPBar:advanceAnimations()
    local now = getTimestampMs()
    local dt = 0
    if self._lastMs then dt = (now - self._lastMs) / 1000 end
    self._lastMs = now
    if dt < 0 then dt = 0 elseif dt > 0.1 then dt = 0.1 end
    local step = dt / DROP_LIFETIME
    local i = 1
    while i <= #self.drops do
        local d = self.drops[i]
        d.age = d.age + step
        if d.age >= 1 then
            table.remove(self.drops, i)
        else
            i = i + 1
        end
    end

    local haloStep = dt / HALO_LIFETIME
    local k = 1
    while k <= #self.halos do
        local hl = self.halos[k]
        hl.age = hl.age + haloStep
        if hl.age >= 1 then table.remove(self.halos, k) else k = k + 1 end
    end
end

-- =============================================================================
-- Render
-- =============================================================================

function NeatXPBar:prerender()
    -- I due versi si decidono qui, una volta per fotogramma, e tutto il disegno
    -- che segue legge questi. Vanno prima del ramo ripiegato: anche li' si
    -- disegnano i numeri.
    self.stackDirNow = self:computeStackDir()
    self.dropDirNow  = self:computeDropDir()
    self:advanceAnimations()

    if self.collapsed then
        self:renderBadge()
        -- Niente di quello che sta sopra la testa dipende dal pannello: i
        -- numeri con la loro opzione, e gli avvisi che hanno preso il posto del
        -- testo del gioco sempre - quelli il gioco li avrebbe mostrati comunque.
        if NeatXPSettings.isDropOverPlayer() then self:renderDrops() end
        self:renderHalos()
        return
    end

    local pad, iconSize, barH, hh = self.pad, self.iconSize, self.barH, self.headerH
    local w, h = self.contentW, self.contentH
    local font = self.font

    local skillType = self.currentSkill
    local perk = skillType and self:getPerk(skillType)
    local level, cur, max, pct = 0, 0, 1, 0
    if perk and self.player then
        level = self.player:getPerkLevel(perk)
        local total = self.player:getXp():getXP(perk)
        max = math.max(1, self:getExpMax(skillType, level))
        cur = self:getExpCurrent(skillType, level, total)
        pct = (level >= 10) and 1 or math.max(0, math.min(cur / max, 1))
    end
    self._pct = pct

    -- Le righe in piu' prima dei drop e prima del pannello: stanno sotto a
    -- tutto, e i numeri devono passargli sopra.
    self:renderExtraRows()
    self:renderDrops()
    self:renderHalos()

    -- Neat window anatomy: rounded MainTitle_BG header + FlatTop body below it.
    NeatXPStyle.drawWindow(self, 0, 0, w, h, hh, 0.95, NeatXPStyle.panelAlpha)

    -- header: [icon] [skill name] ... [level]
    local tr, tg, tb = NeatXPStyle.getColor("text")
    local fh = self.fontH
    local iy = math.floor((hh - iconSize) / 2)
    NeatXPStyle.drawIcon(self, pad, iy, iconSize, skillType, self.currentName, 1.0)

    local lvlStr = NeatXPStyle.tr("IGUI_NeatXP_Level", "Lv") .. " " .. tostring(level)
    local lvlW = getTextManager():MeasureStringX(font, lvlStr)
    local lvlRight = w - pad
    local nameX = pad + iconSize + math.max(4, round(5 * self.scale))
    local textY = math.floor((hh - fh) / 2)
    -- XP potenziati: una freccia arancione prima del livello, finche' il
    -- moltiplicatore dura. E' la stessa condizione con cui il gioco anima le
    -- sue frecce nel pannello abilita' (boostInfo), detta senza dover passare
    -- il mouse sul pannello per il riepilogo.
    local boostW = 0
    local _, multiplied = self:boostInfo(perk)
    if multiplied then
        local arrow = NeatXPStyle.arrowUpIcon()
        if arrow then
            local acc = NeatXPStyle.accent
            boostW = fh + 2
            self:drawTextureScaled(arrow, lvlRight - lvlW - boostW, textY, fh, fh, 1,
                acc.r, acc.g, acc.b)
        end
    end

    local name = NeatXPStyle.fitText(self.currentName, lvlRight - lvlW - boostW - 6 - nameX, font)
    self:drawText(name, nameX, textY, tr, tg, tb, 1, font)
    self:drawTextRight(lvlStr, lvlRight, textY, tr, tg, tb, NeatXPStyle.textDim, font)

    -- body: progress bar with the readout centred inside it
    local readout
    if level >= 10 then
        readout = NeatXPStyle.tr("IGUI_NeatXP_Max", "MAX")
    else
        readout = string.format("%.1f", cur) .. " / " .. string.format("%.0f", max)
    end
    -- Right edge stops short of the corner grip, which sits in the same strip.
    local barW = w - pad - (self.locked and pad or self.barRightReserve)
    NeatXPStyle.drawBar(self, pad, h - pad - barH, barW, barH, pct, readout, font)

    if self.tooltipVisible then
        self:renderTooltip(level, cur, max, pct)
    end
end

function NeatXPBar:renderCollapsed()
    local state = self:isMouseOver() and "hover" or nil
    NeatXPStyle.drawButton(self, 0, 0, self.pillW, self.pillH, state)

    -- Il glifo, non la scritta: e' la stessa immagine dell'icona della mod, e
    -- una lettera disegnata dal font non combacia mai del tutto con una
    -- disegnata a mano. Si conserva la proporzione, quindi la pastiglia puo'
    -- restare piu' larga che alta senza deformarlo.
    local glyph = NeatXPStyle.xpGlyph()
    if glyph then
        local h = math.floor(self.pillH * 0.58)
        local w = math.floor(h * glyph:getWidth() / glyph:getHeight())
        self:drawTextureScaled(glyph,
            math.floor((self.pillW - w) / 2), math.floor((self.pillH - h) / 2),
            w, h, 1, 1, 1, 1)
    else
        self:drawTextCentre("XP", math.floor(self.pillW / 2),
            math.floor((self.pillH - self.fontH) / 2),
            1, 1, 1, 1, self.font)
    end
end

--- Il pannello ripiegato: il badge della mod, non un simbolo qualsiasi.
---
--- E' la stessa immagine che sta nell'elenco delle mod, quindi chi la vede
--- sullo schermo sa gia' di cosa si tratta. Il badge si porta dietro il proprio
--- fondo arancione stondato, quindi qui non ci va nessun tasto sotto: sarebbe
--- una cornice attorno a una cornice.
function NeatXPBar:renderBadge()
    local badge = NeatXPStyle.badgeIcon()
    if not badge then return self:renderCollapsed() end

    local size = math.min(self.pillW, self.pillH)
    local alpha = self:isMouseOver() and 1.0 or 0.75
    self:drawTextureScaled(badge,
        math.floor((self.pillW - size) / 2), math.floor((self.pillH - size) / 2),
        size, size, alpha, 1, 1, 1)
end

--[[ Lo scalino verticale fra un pannello impilato e il successivo.

    Non e' un margine estetico: e' lo spazio in cui salgono i numeri di quella
    riga, e la misura viene dal conto che garantisce che non tocchino mai il
    pannello sopra.

    Un numero della riga i parte a `i*step - START` e sale di `dropFontH`,
    quindi il suo bordo alto arriva a `i*step - START - dropFontH`. Il fondo del
    pannello sopra sta a `i*step - step + contentH`, cioe' `i*step - gap` dove
    `gap = step - contentH`. Perche' non si tocchino serve

        gap >= dropFontH + START + margine

    e questo e' esattamente il valore qui sotto, con quattro pixel di margine.
    Cambiando START o la salita, va rifatto il conto.
]]
function NeatXPBar:stackDropStart()
    return round(4 * self.scale)
end

function NeatXPBar:stackStep()
    return self.contentH + self.dropFontH + self:stackDropStart() + 4
end

--[[ I due versi, e perche' il conto qui sopra vale lo stesso.

    Le righe in piu' possono stare sotto il pannello o sopra; i numeri possono
    salire o scendere. Sono due opzioni indipendenti, quindi quattro
    combinazioni, e in tutte e quattro deve valere la stessa cosa: **un numero
    non tocca mai il pannello che ha davanti a se'.**

    Il conto di `stackStep` non cambia, perche' e' simmetrico: dice quanto vuoto
    serve fra due pannelli, non da che parte. Cambia solo chi ha il vuoto
    davanti.

    Un numero della riga r viaggia nel verso `dropDir`. Il pannello che potrebbe
    incontrare e' quello della riga adiacente in quel verso:

      * se i numeri vanno **nello stesso verso in cui crescono le righe**, il
        vicino e' r+1 - e non c'e' se r e' l'ultima;
      * se vanno **contro**, il vicino e' r-1 - e non c'e' se r e' zero, cioe'
        il pannello principale.

    Chi ha un vicino sale (o scende) solo dentro lo scalino. Chi non ce l'ha ha
    cielo libero e si muove come ha sempre fatto.
]]

--[[ Il verso scelto e il verso usato non sono la stessa cosa.

    L'opzione dice la **preferenza**; se da quella parte non c'e' schermo, si va
    dall'altra. Un pannello disegnato sotto il bordo basso non e' una scelta
    dell'utente: e' un pannello che non esiste. Il ribaltamento e' automatico e
    momentaneo - spostando il pannello verso il centro si torna alla preferenza,
    perche' il conto si rifa' a ogni fotogramma.

    Il conto e' sull'ingombro vero: n righe sono `n*step`, piu' l'altezza
    dell'ultima, piu' un margine che tiene dentro anche il numero che le sale (o
    scende) accanto. Se non ci sta ne' di qua ne' di la' - pannello grande su
    schermo piccolo - si tiene la preferenza: a quel punto e' indifferente.
]]
--- Ricalcolato una volta per fotogramma da `prerender`: chiamarlo dentro a ogni
--- `rowTop` vorrebbe dire una domanda al motore per riga e per numero.
function NeatXPBar:computeStackDir()
    local want = NeatXPSettings.isStackAbove() and -1 or 1
    local n = #self.extraRows
    if n == 0 or not NeatXPSettings.isStackPanels() then return want end

    local screenH = getCore():getScreenHeight()
    local step = self:stackStep()
    local top = self:getAbsoluteY()
    local margin = self.dropFontH + round(8 * self.scale)

    local function fits(d)
        if d > 0 then return top + n * step + self.contentH + margin <= screenH end
        return top - n * step - margin >= 0
    end

    if fits(want) then return want end
    if fits(-want) then return -want end
    return want
end

--- +1 se le righe in piu' crescono verso il basso, -1 se verso l'alto.
function NeatXPBar:stackDir()
    return self.stackDirNow or (NeatXPSettings.isStackAbove() and -1 or 1)
end

--- Come sopra, per i numeri: se dalla parte scelta il numero finirebbe fuori
--- schermo si ribalta. Un numero fuori schermo e' un numero che non c'e', e
--- nessuno sceglie quello.
function NeatXPBar:computeDropDir()
    local want = NeatXPSettings.isDropDown() and 1 or -1
    -- Sopra il personaggio il pannello non c'entra: si sale e basta.
    if NeatXPSettings.isDropOverPlayer() then return want end

    local screenH = getCore():getScreenHeight()
    local top = self:getAbsoluteY()
    -- Quanto serve oltre il bordo del pannello perche' il numero si veda tutto.
    local need = round(18 * self.scale) + round(30 * self.scale) + self.dropFontH

    local function room(d)
        if d > 0 then return top + self.contentH + need <= screenH end
        return top - need >= 0
    end

    if room(want) then return want end
    if room(-want) then return -want end
    return want
end

--- +1 se i numeri scendono, -1 se salgono.
function NeatXPBar:dropDir()
    return self.dropDirNow or (NeatXPSettings.isDropDown() and 1 or -1)
end

--- Il bordo alto della riga r, in coordinate dell'elemento.
function NeatXPBar:rowTop(row)
    return self:stackDir() * row * self:stackStep()
end

--- A quale riga appartiene un'abilita': 0 e' il pannello principale, 1 e 2 le
--- righe in piu'. nil se quell'abilita' non e' piu' su nessuna.
function NeatXPBar:rowOf(skillType)
    if skillType == self.currentSkill then return 0 end
    -- A opzione spenta le righe non si disegnano, e un numero che le inseguisse
    -- salirebbe da un pannello che non c'e'. Puo' capitare per un fotogramma,
    -- fra lo spegnimento dell'opzione e il prossimo XP che sgombra la lista.
    if not NeatXPSettings.isStackPanels() then return 0 end
    for i, row in ipairs(self.extraRows) do
        if row.skill == skillType then return i end
    end
    return nil
end

--- C'e' un pannello subito davanti alla riga r, nel verso in cui viaggiano i
--- numeri? Se si', il numero deve stare dentro lo scalino.
function NeatXPBar:rowHasNeighbour(row)
    local neighbour
    if self:dropDir() == self:stackDir() then
        neighbour = row + 1
    else
        neighbour = row - 1
    end
    if neighbour < 0 then return false end
    if neighbour == 0 then return true end
    return neighbour <= #self.extraRows and NeatXPSettings.isStackPanels()
end

--[[ Dove ancorare i numeri quando salgono sopra il personaggio.

    `isoToScreenX/Y` sono le stesse che usa il gioco per appoggiare roba addosso
    a qualcuno - la barra della tensione quando peschi, le icone del foraging,
    i suggerimenti dei tasti (TensionUI.lua:11, ISBaseIcon.lua:167). Prendono
    l'indice del giocatore e una posizione nel mondo e restituiscono pixel di
    schermo, che qui vanno riportati dentro le coordinate dell'elemento.

    Lo `z` alzato di 0.9 e' quello che porta il punto sopra la testa invece che
    ai piedi: vanilla usa +0.6 per una barra che sta all'altezza del petto.

    Torna nil se non si puo' rispondere: senza giocatore, o se il motore non
    espone quelle funzioni, i numeri tornano semplicemente sopra il pannello.
]]
function NeatXPBar:playerAnchor()
    local p = self.player
    if not p then return nil end
    if type(isoToScreenX) ~= "function" or type(isoToScreenY) ~= "function" then return nil end

    local ok, sx, sy = pcall(function()
        local z = p:getZ() + 0.9
        return isoToScreenX(self.playerIndex, p:getX(), p:getY(), z),
               isoToScreenY(self.playerIndex, p:getX(), p:getY(), z)
    end)
    if not ok or type(sx) ~= "number" or type(sy) ~= "number" then return nil end

    return sx - self:getAbsoluteX(), sy - self:getAbsoluteY()
end

function NeatXPBar:renderDrops()
    local w = self.contentW
    local size = math.floor(self.iconSize * 0.58)
    local fr, fg, fb = NeatXPStyle.getFillColor(self._pct or 0)
    local font, ih = self.dropFont, self.dropFontH
    local edge = math.max(4, round(6 * self.scale))

    -- Sopra il personaggio: i numeri lasciano il pannello e seguono lui. Le
    -- righe impilate qui non contano piu' - c'e' un solo posto da cui salire -
    -- e i drop restano staccati fra loro grazie all'attesa che gia' c'era.
    local ax, ay
    if NeatXPSettings.isDropOverPlayer() then ax, ay = self:playerAnchor() end

    for _, d in ipairs(self.drops) do
        -- Eta negativa = ancora in coda: non si disegna finche non tocca lo zero.
        if d.age >= 0 then
        local a = math.min(1, (1 - d.age) * 1.8)

        -- Ogni numero parte dalla riga che mostra la sua abilita' e va nel verso
        -- scelto. Se da quella parte ha cielo libero si muove come ha sempre
        -- fatto; se ha un pannello davanti, si muove al massimo di quanto e' lo
        -- scalino - che e' esattamente lo spazio vuoto fino a quel pannello.
        -- Cosi' due numeri di due abilita' diverse non si incrociano mai, e la
        -- cosa vale in tutte e quattro le combinazioni di verso.
        local amount = "+" .. string.format("%.1f", d.amount)
        local tw = getTextManager():MeasureStringX(font, amount)

        local dy, right
        if ay then
            -- Sopra il personaggio: icona e numero, niente altro. La freccia in
            -- su non sta qui - li' significherebbe "sto salendo", che e' ovvio.
            -- Il suo posto e' il riepilogo dell'abilita', dove vuol dire una
            -- cosa sola: c'e' un moltiplicatore attivo.
            --
            -- Il verso sopra/sotto non vale qui: sopra la testa non c'e' nessun
            -- pannello da scavalcare, e i numeri partono sempre verso l'alto.
            dy = ay - round(26 * self.scale) - round(30 * self.scale) * d.age
            right = ax + math.floor((tw + size + 2) / 2)
        else
            local row = self:rowOf(d.skill) or 0
            local startOff, headroom
            if self:rowHasNeighbour(row) then
                -- C'e' un pannello davanti: si viaggia solo dentro lo scalino.
                startOff, headroom = self:stackDropStart(), self.dropFontH
            else
                -- Cielo libero da quella parte.
                startOff, headroom = round(18 * self.scale), round(30 * self.scale)
            end

            local top = self:rowTop(row)
            if self:dropDir() < 0 then
                -- In su: `dy` e' il bordo alto del testo, e parte startOff sopra
                -- il bordo alto del pannello.
                dy = top - startOff - headroom * d.age
            else
                -- In giu', speculare: e' il bordo **basso** del testo a stare
                -- startOff sotto il bordo basso del pannello, quindi il bordo
                -- alto sta una riga di testo piu' su.
                dy = top + self.contentH - ih + startOff + headroom * d.age
            end
            right = w - edge
        end

        self:drawTextRight(amount, right + 1, dy + 1, 0, 0, 0, a * 0.7, font)
        self:drawTextRight(amount, right, dy, fr, fg, fb, a, font)

        local ix = right - tw - size - 2
        NeatXPStyle.drawIcon(self, ix, dy + math.floor((ih - size) / 2), size, d.skill, d.name, a)
        end
    end
end

--- Gli avvisi che prendono il posto di quelli di radio e TV: freccia, a volte
--- l'icona dell'abilita', e il nome - sopra la testa, dove stavano. Salgono piu'
--- lentamente dei numeri e restano di piu', perche' sono una frase da leggere,
--- non una cifra da cogliere al volo.
---
--- Il colore lo porta l'avviso, non lo sceglie qui: verde o rosso secondo la
--- regola di vanilla. L'arancione Neat direbbe "questa e' roba della mod", che
--- e' l'unica cosa che un avviso di noia non deve dire.
function NeatXPBar:renderHalos()
    if #self.halos == 0 then return end

    local ax, ay = self:playerAnchor()
    if not ay then return end

    local font, fh = self.font, self.fontH
    local size = math.floor(self.iconSize * 0.58)

    for i, hl in ipairs(self.halos) do
        local a = math.min(1, (1 - hl.age) * 2.2)
        -- Impilati fra loro se ne arriva piu' d'uno: il piu' vecchio sta sopra.
        local stackOff = (#self.halos - i) * (fh + 3)
        local y = ay - round(44 * self.scale) - round(22 * self.scale) * hl.age - stackOff
        local iconY = y + math.floor((fh - size) / 2)

        local col = NeatXPStyle.haloColor(hl.good)
        local arrow = (hl.up ~= nil) and NeatXPStyle.arrowIcon(hl.up) or nil

        local tw = getTextManager():MeasureStringX(font, hl.name)
        local total = tw
            + (arrow and (size + 2) or 0)
            + (hl.icon and (size + 2) or 0)
        local x = ax - math.floor(total / 2)

        if arrow then
            self:drawTextureScaled(arrow, x, iconY, size, size, a, col.r, col.g, col.b)
            x = x + size + 2
        end
        if hl.icon then
            NeatXPStyle.drawIcon(self, x, iconY, size, hl.skill, hl.name, a)
            x = x + size + 2
        end

        self:drawText(hl.name, x + 1, y + 1, 0, 0, 0, a * 0.7, font)
        self:drawText(hl.name, x, y, col.r, col.g, col.b, a, font)
    end
end

--- Le righe sotto il pannello principale: stessa forma, stessa misura, stessa
--- anatomia. Sono disegnate fuori dai bordi dell'elemento e non ricevono clic.
function NeatXPBar:renderExtraRows()
    if #self.extraRows == 0 then return end
    -- Spegnendo l'opzione le righe spariscono subito, senza aspettare il
    -- prossimo XP o la scadenza del silenzio.
    if not NeatXPSettings.isStackPanels() then return end

    local pad, iconSize, barH, hh = self.pad, self.iconSize, self.barH, self.headerH
    local w, h = self.contentW, self.contentH
    local font, fh = self.font, self.fontH
    local tr, tg, tb = NeatXPStyle.getColor("text")

    for i, row in ipairs(self.extraRows) do
        -- Sopra o sotto lo decide rowTop: qui la riga e' sempre "la i-esima".
        local oy = self:rowTop(i)
        local perk = self:getPerk(row.skill)
        local level, cur, max, pct = 0, 0, 1, 0
        if perk and self.player then
            level = self.player:getPerkLevel(perk)
            local total = self.player:getXp():getXP(perk)
            max = math.max(1, self:getExpMax(row.skill, level))
            cur = self:getExpCurrent(row.skill, level, total)
            pct = (level >= 10) and 1 or math.max(0, math.min(cur / max, 1))
        end

        NeatXPStyle.drawWindow(self, 0, oy, w, h, hh, 0.95, NeatXPStyle.panelAlpha)

        local iy = oy + math.floor((hh - iconSize) / 2)
        NeatXPStyle.drawIcon(self, pad, iy, iconSize, row.skill, row.name, 1.0)

        local lvlStr = NeatXPStyle.tr("IGUI_NeatXP_Level", "Lv") .. " " .. tostring(level)
        local lvlW = getTextManager():MeasureStringX(font, lvlStr)
        local lvlRight = w - pad
        local nameX = pad + iconSize + math.max(4, round(5 * self.scale))
        local textY = oy + math.floor((hh - fh) / 2)
        local name = NeatXPStyle.fitText(row.name, lvlRight - lvlW - 6 - nameX, font)
        self:drawText(name, nameX, textY, tr, tg, tb, 1, font)
        self:drawTextRight(lvlStr, lvlRight, textY, tr, tg, tb, NeatXPStyle.textDim, font)

        local readout
        if level >= 10 then
            readout = NeatXPStyle.tr("IGUI_NeatXP_Max", "MAX")
        else
            readout = string.format("%.1f", cur) .. " / " .. string.format("%.0f", max)
        end
        -- Niente grip su queste: la maniglia sta solo sul pannello vero, quindi
        -- la barra puo' arrivare fino al bordo come quando e' bloccato.
        NeatXPStyle.drawBar(self, pad, oy + h - pad - barH, w - pad * 2, barH, pct, readout, font)
    end
end

--[[ Il ritmo di guadagno dell'abilita' mostrata, se c'e' qualcosa da dire.

    Sono due cose diverse e le leggiamo tutte e due dal gioco:

      * `getPerkBoost` vale 0..3 e nel gioco si traduce in 50/75/100/125% - e'
        il ritmo che il personaggio ha per quell'abilita', deciso da mestiere e
        tratti. La corrispondenza e' quella di vanilla, presa dalla sua stessa
        schermata (ISPlayerStatsUI.lua:730-739): non e' inventata qui.
      * `getMultiplier` maggiore di zero vuol dire che in questo momento c'e' un
        moltiplicatore attivo - e' la stessa condizione con cui il pannello
        abilita' del gioco anima le sue tre frecce (ISCharacterInfo.lua:155).

    La riga compare solo quando una delle due ha qualcosa da dire: a ritmo
    normale e senza moltiplicatore sarebbe una riga che dice "tutto come al
    solito". Il numero e' sempre il ritmo; la freccia dice che sopra c'e' anche
    un moltiplicatore.
]]
local BOOST_RATE = { [0] = "50%", [1] = "75%", [2] = "100%", [3] = "125%" }

--- Livello e avanzamento di un'abilita' qualsiasi, non solo di quella mostrata.
--- La usano il riepilogo del pannello e quello della finestra di
--- configurazione, cosi' i due non possono raccontare cose diverse.
---@return number level, number cur, number max, number pct
function NeatXPBar:skillStats(skillType)
    local perk = skillType and self:getPerk(skillType)
    if not (perk and self.player) then return 0, 0, 1, 0 end

    local level = self.player:getPerkLevel(perk)
    local total = self.player:getXp():getXP(perk)
    local max = math.max(1, self:getExpMax(skillType, level))
    local cur = self:getExpCurrent(skillType, level, total)
    local pct = (level >= 10) and 1 or math.max(0, math.min(cur / max, 1))
    return level, cur, max, pct
end

---@return string|nil rate, boolean multiplied
function NeatXPBar:boostInfo(perk)
    if not (perk and self.player) then return nil, false end

    local ok, xp = pcall(function() return self.player:getXp() end)
    if not ok or not xp then return nil, false end

    local boost, mult = 0, 0
    pcall(function() boost = xp:getPerkBoost(perk:getType()) or 0 end)
    pcall(function() mult = xp:getMultiplier(perk:getType()) or 0 end)

    if boost <= 0 and mult <= 0 then return nil, false end
    return BOOST_RATE[boost] or BOOST_RATE[0], mult > 0
end

function NeatXPBar:renderTooltip(level, cur, max, pct)
    local w = self.contentW
    local font, fh = self.font, self.fontH
    local pad = math.max(6, round(8 * self.scale))
    self._ttHeaderH = fh + round(8 * self.scale)
    local tw = math.max(w + round(40 * self.scale), round(190 * self.scale))

    local perk = self.currentSkill and self:getPerk(self.currentSkill)
    local rate, multiplied = self:boostInfo(perk)

    local rowCount = rate and 5 or 4
    local th = self._ttHeaderH + 6 + rowCount * (fh + 2) + 8
    local ty = self.contentH + 6
    if self:getY() + ty + th > getCore():getScreenHeight() then
        ty = -6 - th   -- not enough room below: show above the bar
    end
    local tx = math.floor((w - tw) / 2)

    local minX = -self:getX()
    local maxX = getCore():getScreenWidth() - self:getX()
    if tx < minX then tx = minX end
    if tx + tw > maxX then tx = maxX - tw end

    -- Rocco anatomy: rounded MainTitle_BG header + FlatTop body below it
    -- (drawing a square strip over a full-height panel leaves stray corners).
    NeatXPStyle.drawWindow(self, tx, ty, tw, th, self._ttHeaderH, 1.0, 1.0)
    local acc = NeatXPStyle.accent
    local tr, tg, tb = NeatXPStyle.getColor("text")
    local hy = ty + math.floor((self._ttHeaderH - fh) / 2)
    self:drawText(self.currentName, tx + pad, hy, acc.r, acc.g, acc.b, 1, font)
    self:drawTextRight(NeatXPStyle.tr("IGUI_NeatXP_Level", "Lv") .. " " .. tostring(level),
        tx + tw - pad, hy, tr, tg, tb, 1, font)

    local remaining = math.max(0, max - cur)
    local rows = {
        { NeatXPStyle.tr("IGUI_NeatXP_Current", "Current:"),      string.format("%.1f", cur) },
        { NeatXPStyle.tr("IGUI_NeatXP_NextLevel", "Next level:"), string.format("%.0f", max) },
        { NeatXPStyle.tr("IGUI_NeatXP_Remaining", "Remaining:"),  string.format("%.1f", remaining) },
        { NeatXPStyle.tr("IGUI_NeatXP_Progress", "Progress:"),    tostring(math.floor(pct * 100)) .. "%" },
    }
    local py = ty + self._ttHeaderH + 5
    for i, row in ipairs(rows) do
        local ry = py + (i - 1) * (fh + 2)
        self:drawText(row[1], tx + pad, ry, 1, 1, 1, NeatXPStyle.textDim, font)
        self:drawTextRight(row[2], tx + tw - pad, ry, tr, tg, tb, 1, font)
    end

    -- Il ritmo, ultima riga. Il numero e' arancione perche' e' una condizione
    -- attiva, come il lucchetto; la freccia gli sta a sinistra e compare solo
    -- se c'e' anche un moltiplicatore.
    if rate then
        local ry = py + #rows * (fh + 2)
        self:drawText(NeatXPStyle.tr("IGUI_NeatXP_XpRate", "XP rate:"),
            tx + pad, ry, 1, 1, 1, NeatXPStyle.textDim, font)
        self:drawTextRight(rate, tx + tw - pad, ry, acc.r, acc.g, acc.b, 1, font)

        if multiplied then
            local arrow = NeatXPStyle.arrowUpIcon()
            local rw = getTextManager():MeasureStringX(font, rate)
            if arrow then
                local asz = fh
                self:drawTextureScaled(arrow, tx + tw - pad - rw - asz - 2, ry,
                    asz, asz, 1, acc.r, acc.g, acc.b)
            else
                self:drawTextRight("^", tx + tw - pad - rw - 2, ry, acc.r, acc.g, acc.b, 1, font)
            end
        end
    end
end

-- =============================================================================
-- Input
-- =============================================================================

function NeatXPBar:onMouseMove(dx, dy)
    self.tooltipVisible = not self.collapsed
    ISPanel.onMouseMove(self, dx, dy)
end

function NeatXPBar:onMouseMoveOutside(dx, dy)
    self.tooltipVisible = false
    ISPanel.onMouseMoveOutside(self, dx, dy)
end

function NeatXPBar:onMouseDown(x, y)
    -- remember where we started so onMouseUp can tell a click from a drag
    self._pressX, self._pressY = self:getX(), self:getY()
    if not self.locked then
        ISPanel.onMouseDown(self, x, y)
    end
    return true
end

function NeatXPBar:onMouseUp(x, y)
    ISPanel.onMouseUp(self, x, y)
    local moved = math.abs(self:getX() - (self._pressX or self:getX()))
                + math.abs(self:getY() - (self._pressY or self:getY()))

    -- a click on the collapsed pill re-opens the panel in place
    if moved < 4 and self.collapsed then
        self:setCollapsed(false)
    end
    self:writeConfig()   -- persist position / state after any drag or toggle
    return true
end

function NeatXPBar:onMouseUpOutside(x, y)
    ISPanel.onMouseUpOutside(self, x, y)
    self:writeConfig()
end

-- Right-click is the only way into the menu: the old hamburger button in the
-- header is gone.
--- Il click destro apre direttamente la configurazione.
---
--- Prima apriva un menu di due voci, Configura e Nascondi, e la seconda vive
--- meglio dentro il pannello: nasconderla e' una cosa che si fa una volta, non
--- una che vale un menu tutto suo davanti a quella che si usa sempre.
function NeatXPBar:onRightMouseDown(x, y)
    if self.collapsed then return true end
    self:openConfig()
    return true
end

function NeatXPBar:setCollapsed(v)
    if self.collapsed == v then return end
    self.collapsed = v
    self.tooltipVisible = false
    if v then self.drops = {} end
    self:layout()
end

function NeatXPBar:isLocked() return self.locked == true end

function NeatXPBar:setLocked(v)
    self.locked = v and true or false
    self.moveWithMouse = not self.locked
    self:positionResizeWidget()
    self:writeConfig()
end

function NeatXPBar:toggleLocked() self:setLocked(not self.locked) end

function NeatXPBar:openConfig()
    if self.configPanel == nil and NeatXPConfig then
        self.configPanel = NeatXPConfig:new(self)
        self.configPanel:initialise()
        self.configPanel:addToUIManager()
    elseif self.configPanel then
        self.configPanel:setVisible(true)
        self.configPanel:addToUIManager()
        self.configPanel:bringToTop()
    end
end

-- Reachable from the key binding: opens the config even when the bar has been
-- collapsed or dragged somewhere awkward.
function NeatXPBar:toggleConfig()
    if self.configPanel and self.configPanel:getIsVisible() then
        self.configPanel:close()
    else
        self:openConfig()
    end
end

-- Called from Mod Options; also restores the default size, since a panel dragged
-- to three times its width is just as easy to lose as one dragged off-screen.
function NeatXPBar:resetPosition()
    self:setCollapsed(false)
    self.scale = 1.0
    self:computeMetrics()
    self:layout()
    self:setX(getCore():getScreenWidth() - 360)
    self:setY(180)
    self:clampToScreen()
    self:writeConfig()
end

-- A saved position from a larger monitor (or a resolution change) used to park
-- the bar outside the viewport, where it could no longer be clicked at all.
function NeatXPBar:clampToScreen()
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local x = math.max(0, math.min(self:getX(), sw - self:getWidth()))
    local y = math.max(0, math.min(self:getY(), sh - self:getHeight()))
    self:setX(x)
    self:setY(y)
end

-- =============================================================================
-- Player / persistence
-- =============================================================================

function NeatXPBar:getPlayer() return self.player end

function NeatXPBar:setPlayer(idx, player)
    self.playerIndex = idx
    self.player = player
    self.player_isDead = false
    self.drops = {}
    self:refreshSnapshot()
end

function NeatXPBar:getPlayerIsDead() return self.player_isDead end

function NeatXPBar:setPlayerIsDead(v)
    self.player_isDead = v
    if v then self.drops = {} end
end

function NeatXPBar:writeConfig()
    local f = getFileWriter("NeatXPDrops.ini", true, false)
    if f == nil then return end
    f:write("pos_x=" .. tostring(self:getX()) .. "\n")
    f:write("pos_y=" .. tostring(self:getY()) .. "\n")
    f:write("scale=" .. string.format("%.4f", self.scale) .. "\n")
    f:write("collapsed=" .. tostring(self.collapsed) .. "\n")
    f:write("locked=" .. tostring(self.locked) .. "\n")
    f:write("lastSkill=" .. tostring(self.currentSkill) .. "\n")
    for skillType, v in pairs(self.tracked) do
        f:write("track_" .. skillType .. "=" .. tostring(v) .. "\n")
    end
    f:close()
end

function NeatXPBar:readConfig()
    local f = getFileReader("NeatXPDrops.ini", false)
    if f == nil then return end

    -- Collected first, applied in a fixed order: the scale decides the panel
    -- size, and the size decides how the saved position gets clamped.
    local kv = {}
    local line = f:readLine()
    while line ~= nil do
        local p = string.split(line, "=")
        if p and #p == 2 then kv[p[1]] = p[2] end
        line = f:readLine()
    end
    f:close()

    if kv.scale then self.scale = math.max(MIN_SCALE, math.min(tonumber(kv.scale) or 1, MAX_SCALE)) end
    self.locked = (kv.locked == "true")
    self.moveWithMouse = not self.locked
    self.collapsed = (kv.collapsed == "true")
    self:computeMetrics()
    self:layout()

    if kv.pos_x then self:setX(tonumber(kv.pos_x) or self:getX()) end
    if kv.pos_y then self:setY(tonumber(kv.pos_y) or self:getY()) end
    if kv.lastSkill and self.perkIndices[kv.lastSkill] then self:setSkill(kv.lastSkill) end

    for k, v in pairs(kv) do
        if string.sub(k, 1, 6) == "track_" then
            local s = string.sub(k, 7)
            if self.perkIndices[s] then self.tracked[s] = (v == "true") end
        end
    end

    self:clampToScreen()
end
