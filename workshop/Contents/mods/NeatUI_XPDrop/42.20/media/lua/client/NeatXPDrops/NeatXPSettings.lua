--[[ ============================================================================
    NeatXPSettings - Options > Mods > "NeatUI XP Drop".

    Holds everything that is not per-character UI state:
      * Hide the mod entirely (the collapsed "XP" pill goes away too)
      * Reset position (moved here from the bar's right-click menu)
      * Progress-bar gradient start / end colours
      * Panel text colour (skill name, level, and the readout numbers)

    Colour rows are the stock PZAPI "colorpicker" option, but the swatch button
    opens NeatXPColorPicker instead of the 84-square vanilla mosaic: the mosaic
    cannot express a gradient stop, and it does not look like a Neat window.
    MainOptions.onModColorPick is wrapped rather than replaced, so every other
    mod's colour options keep the vanilla picker.
============================================================================ ]]--

require "NeatXPDrops/NeatXPStyle"
require "NeatXPDrops/NeatXPColorPicker"

NeatXPSettings = NeatXPSettings or {}

NeatXPSettings.MOD_ID    = "NeatUI_XPDrop"
NeatXPSettings.MOD_TITLE = "NeatUI XP Drop"

local PREFIX = NeatXPSettings.MOD_ID .. "."

-- optionId -> { colourKey, title key/fallback, default rgb }
local COLOR_OPTIONS = {
    barColorStart = { key = "barStart", title = { "IGUI_NeatXP_Opt_BarStart", "Progress bar - start colour" } },
    barColorEnd   = { key = "barEnd",   title = { "IGUI_NeatXP_Opt_BarEnd",   "Progress bar - end colour" } },
    textColor     = { key = "text",     title = { "IGUI_NeatXP_Opt_TextColor", "Panel text colour" } },
}

local _loaded = false

local function toBool(v)
    return v == true or v == 1 or v == "1" or v == "true"
end

local function getOptions()
    return PZAPI and PZAPI.ModOptions and PZAPI.ModOptions:getOptions(NeatXPSettings.MOD_ID)
end

local function getOption(id)
    local o = getOptions()
    return o and o:getOption(id)
end

-- =============================================================================
-- Public state
-- =============================================================================

function NeatXPSettings.isHidden()
    local o = getOption("hideMod")
    if not o then return false end
    -- Only worth loading once our own block exists: PZAPI:load() shunts every
    -- unknown line into OtherOptions, so calling it before registration would
    -- read nothing and still latch _loaded.
    if not _loaded and type(PZAPI.ModOptions.load) == "function" then
        pcall(function() PZAPI.ModOptions:load() end)
        _loaded = true
    end
    return toBool(o:getValue())
end

-- NeatXPDrops.lua registers itself here so a live toggle takes effect without
-- a reload.
NeatXPSettings.hiddenCallbacks = NeatXPSettings.hiddenCallbacks or {}
NeatXPSettings.autoHideCallbacks = NeatXPSettings.autoHideCallbacks or {}

--- Nascondi automaticamente: il pannello sparisce del tutto e ricompare solo
--- quando arrivano XP di un'abilita' seguita.
function NeatXPSettings.isAutoHide()
    local o = getOption("autoHide")
    return o ~= nil and toBool(o:getValue())
end

--- Pannelli impilati: quando piu' abilita' prendono XP a poca distanza, invece
--- di scavalcarsi nello stesso pannello ne compaiono altri sotto, fino a tre.
--- Si legge al volo e non ha bisogno di richiami: chi la usa la chiede al
--- momento di disegnare, e cambiare l'opzione si vede al fotogramma dopo.
function NeatXPSettings.isStackPanels()
    local o = getOption("stackPanels")
    return o ~= nil and toBool(o:getValue())
end

--- Le righe in piu' compaiono **sopra** il pannello invece che sotto. Serve a
--- chi tiene il pannello in basso: li' le righe sotto finirebbero fuori
--- schermo.
function NeatXPSettings.isStackAbove()
    local o = getOption("stackAbove")
    return o ~= nil and toBool(o:getValue())
end

--- I numeri scendono **sotto** il pannello invece di salire sopra. Stesso
--- motivo dell'opzione qui sopra, ribaltato: chi tiene il pannello in alto,
--- attaccato al bordo, i numeri sopra non li vede.
function NeatXPSettings.isDropDown()
    local o = getOption("dropDown")
    return o ~= nil and toBool(o:getValue())
end

--- I numeri salgono sopra la testa del personaggio invece che sopra il
--- pannello. Il pannello resta dov'e' e continua a fare il resto.
function NeatXPSettings.isDropOverPlayer()
    local o = getOption("dropOverPlayer")
    return o ~= nil and toBool(o:getValue())
end

--- Quanto sono grandi i numeri, rispetto al testo del pannello. "Normale" e'
--- la misura di sempre (1.55); le altre ci stanno attorno. Valgono sopra il
--- pannello e sopra il personaggio: e' lo stesso carattere.
local DROP_SIZES = { 1.15, 1.55, 2.1, 2.8 }
local DROP_SIZE_DEFAULT = 2

-- `pending`: il valore appena scelto. Il pannello delle opzioni chiama i
-- richiami **prima** di scriverlo nell'opzione (MainOptions.lua, ramo combobox),
-- quindi li' getValue darebbe ancora quello vecchio.
local pending = nil

function NeatXPSettings.dropSizeFactor()
    local i = pending
    if i == nil then
        local o = getOption("dropSize")
        i = o and tonumber(o:getValue()) or DROP_SIZE_DEFAULT
    end
    return DROP_SIZES[i] or DROP_SIZES[DROP_SIZE_DEFAULT]
end

--- Il pannello rifa' le sue misure quando cambia la misura dei numeri: i
--- caratteri si scelgono li', non a ogni fotogramma.
local function applyDropSize(value)
    pending = tonumber(value)
    local bar = NeatXPDrops and NeatXPDrops.bar
    if bar and bar.computeMetrics then
        bar:computeMetrics()
        if bar.layout then bar:layout() end
    end
    pending = nil
end

--- Sostituisce i testi XP del gioco con i nostri. Accesa di serie.
function NeatXPSettings.isReplaceVanillaXp()
    local o = getOption("replaceVanillaXp")
    if o == nil then return true end   -- prima che le opzioni esistano: il default
    return toBool(o:getValue())
end

--[[ Sostituire i testi XP del gioco con i nostri.

    Il gioco ne scrive di due tipi, da due posti diversi, e servono due strade.

    **Lavorazione.** Passa da `showCraftingXP`, l'opzione che il gioco stesso
    offre in Opzioni (MainOptions.lua:1299-1308) e che il motore legge da Java.
    Non c'e' altro modo di intervenire: si spegne la sua.

    **Radio e TV.** Passa da Lua, ed e' raggiungibile:
    `ISRadioInteractions:getInstance()` restituisce un singleton con dentro
    `addHalo`, chiamata da `ISRadioInteractions.lua` sia quando un programma
    insegna un'abilita' (riga 19) sia quando muove noia, infelicita', stress e
    compagnia (righe 29, 40, 83). Qui non ci si limita a zittirla: si intercetta
    e si rimette la stessa informazione con la nostra freccia e il nostro
    carattere, sopra la testa dov'era. E' il motivo per cui l'opzione si chiama
    "sostituisci" e non "nascondi".

    **Passa tutto, non solo l'XP.** All'inizio filtravamo: solo le righe il cui
    testo era il nome di un'abilita'. Il risultato era due stili sopra la stessa
    testa nella stessa scena - un programma alla TV insegna e annoia insieme -
    che e' peggio di non sostituire niente. Adesso passa di qui ogni avviso di
    radio e TV, e l'icona dell'abilita' si aggiunge quando il testo e' il nome
    di una.

    **Il verso e il colore vengono da `_amount`, con la regola di vanilla**
    (`ISRadioInteractions.lua:308-333`): il segno decide la freccia, e
    `_inverseCols` decide se salire e' una buona notizia. Per un'abilita' e'
    vero - piu' XP e' meglio; per la noia e' falso - piu' noia e' peggio. La
    regola non la reinventiamo: la ricopiamo, o due avvisi affiancati direbbero
    cose diverse.

    **Cosa resta scoperto:** `noHalo`, l'elenco con cui una mod puo' zittire un
    tipo di avviso, e' una locale dentro quel file e non e' leggibile da qui. Un
    avviso zittito da altri, con questa opzione accesa, tornerebbe visibile.
    Nessuna mod fra quelle che conosciamo usa `setNoHalo`.

    L'unica cosa che tocchiamo fuori casa nostra e' `showCraftingXP`, e si
    rimette com'era appena l'opzione si spegne.
]]
local _haloHooked = false

--- I nomi di tutte le abilita', come li scrive il gioco. Costruito una volta
--- sola alla prima chiamata: prima dell'avvio della partita PerkFactory non ha
--- ancora niente da dire.
local _perkNames = nil
local function perkNames()
    if _perkNames then return _perkNames end
    local names = {}
    local ok = pcall(function()
        for i = 1, Perks.getMaxIndex() do
            local perk = PerkFactory.getPerk(Perks.fromIndex(i - 1))
            if perk then
                local n = perk:getName()
                if n and n ~= "" then names[n] = true end
            end
        end
    end)
    if not ok then return nil end       -- riproveremo al prossimo giro
    _perkNames = names
    return _perkNames
end

--- Spegne o riaccende il testo XP di lavorazione del gioco.
---
--- E' l'unica impostazione del gioco che tocchiamo, e si rimette a posto da
--- sola quando l'opzione nostra si spegne. L'unico caso scoperto e'
--- disinstallare la mod con l'opzione accesa: li' resta spenta, e va rimessa a
--- mano da Opzioni.
function NeatXPSettings.applyCraftingXp(replace)
    local core = getCore()
    if not (core and core.setOptionShowCraftingXP) then return end
    pcall(function() core:setOptionShowCraftingXP(not replace) end)
end

function NeatXPSettings.hookVanillaHalo()
    if _haloHooked then return end
    if type(ISRadioInteractions) ~= "table" or not ISRadioInteractions.getInstance then return end

    local ok, inst = pcall(function() return ISRadioInteractions:getInstance() end)
    if not ok or type(inst) ~= "table" or type(inst.addHalo) ~= "function" then return end

    _haloHooked = true
    local vanilla = inst.addHalo
    inst.addHalo = function(str, amount, inverseCols)
        if NeatXPSettings.isReplaceVanillaXp() and type(str) == "string" and str ~= "" then
            local bar = NeatXPDrops and NeatXPDrops.bar
            if bar and bar.addHalo then
                -- La regola del verso e del colore e' quella di vanilla, presa
                -- da ISRadioInteractions.lua:316-327. Senza numero non c'e'
                -- freccia: e' il caso in cui anche il gioco scrive solo il testo.
                local up, good = nil, true
                if type(amount) == "number" and amount ~= 0 then
                    up = amount > 0
                    -- inverseCols acceso = salire e' una buona notizia (un'abilita').
                    -- Spento = salire e' una brutta notizia (noia, stress).
                    good = (up == (inverseCols == true))
                end

                -- L'icona solo se il testo e' proprio il nome di un'abilita'.
                -- Per la noia non esiste un'icona e inventarne una sarebbe
                -- peggio del nulla.
                local names = perkNames()
                local isSkill = names ~= nil and names[str] == true

                -- Non sparisce: la stessa notizia torna con la nostra faccia.
                bar:addHalo(str, up, good, isSkill)
                return
            end
        end
        return vanilla(str, amount, inverseCols)
    end
end

function NeatXPSettings.registerAutoHideCallback(cb)
    table.insert(NeatXPSettings.autoHideCallbacks, cb)
end

local function fireAutoHide(v)
    for _, cb in ipairs(NeatXPSettings.autoHideCallbacks) do
        pcall(function() cb(v) end)
    end
end

function NeatXPSettings.registerHiddenCallback(cb)
    if type(cb) ~= "function" then return end
    table.insert(NeatXPSettings.hiddenCallbacks, cb)
    pcall(function() cb(NeatXPSettings.isHidden()) end)
end

local function fireHidden(hidden)
    for _, cb in ipairs(NeatXPSettings.hiddenCallbacks) do
        pcall(function() cb(hidden) end)
    end
end

-- =============================================================================
-- Colour plumbing
-- =============================================================================

local function applyColor(colorKey, value)
    if type(value) ~= "table" then return end
    local r = value.r or value[1]
    local g = value.g or value[2]
    local b = value.b or value[3]
    NeatXPStyle.setColor(colorKey, r, g, b)
end

-- Vanilla positioning logic from MainOptions:onModColorPick, kept identical so
-- the panel lands under its swatch button on every resolution.
local function anchorPicker(mainOptions, button, picker)
    local x = button.parent.parent.x + button.parent.x + button.parent:getXScroll() + button.x
    local y = button.parent.parent.y + button.parent.y + button.parent:getYScroll() + button.y + button.height + 1
    if y + picker.height > mainOptions.height then
        y = y - button.height - picker.height - 1
    end
    if y < 0 then y = 0 end
    x = math.min(x, mainOptions.width - picker.width - 4)
    if x < 0 then x = 0 end
    picker:setX(x)
    picker:setY(y)
end

function NeatXPSettings.openNeatPicker(mainOptions, button)
    local optionId = string.sub(button.optionID or "", #PREFIX + 1)
    local meta = COLOR_OPTIONS[optionId]

    local picker = NeatXPColorPicker:new(0, 0,
        meta and NeatXPStyle.tr(meta.title[1], meta.title[2]) or nil)
    picker:initialise()

    -- Default first in the swatch row, so "put it back" is always the first
    -- square; setPalette re-measures the panel, so it runs before anchoring.
    local def = meta and NeatXPStyle.DEFAULTS[meta.key]
    if def then
        picker:setDefaultColor(def.r, def.g, def.b)
        local palette = { { r = def.r, g = def.g, b = def.b } }
        for _, p in ipairs(NeatXPColorPicker.PRESETS or {}) do
            local r, g, b = p.r or p[1], p.g or p[2], p.b or p[3]
            if not (r == def.r and g == def.g and b == def.b) then
                table.insert(palette, { r = r, g = g, b = b })
            end
        end
        picker:setPalette(palette)
    end

    local c = button.backgroundColor or { r = 1, g = 1, b = 1 }
    picker:setInitialColor(ColorInfo.new(c.r, c.g, c.b, 1))

    picker.pickedFunc   = MainOptions.pickedModColor
    picker.pickedTarget = button
    picker.pickedArgs   = {}

    anchorPicker(mainOptions, button, picker)
    mainOptions:addChild(picker)
    picker:setCapture(true)
    picker:setVisible(true)
    picker:bringToTop()
end

--[[ Round off our swatch buttons on the options screen.

    MainOptions:addColorButton hands back a plain square ISButton and PZAPI keeps
    it on `option.element`, so the handle is there - it just does not exist until
    the screen is built. addModOptionsPanel is the moment it does, hence the
    wrapper rather than a one-shot call at boot. Styling latches, so re-opening
    Options costs nothing.
]]
--[[ Disinnesca le etichette che fanno esplodere la pagina Mods.

    `getText` su una stringa che non e' una chiave di traduzione la ridara'
    indietro tale e quale, ma prima la passa dal formattatore Java per
    segnalare l'anomalia - e il messaggio di quella segnalazione, che si porta
    dentro la stringa, finisce a sua volta dentro String.format
    (Translator.reportMissingArgumentsFromPastAbuse -> DebugLogStream.
    printException). Un '%' isolato nell'etichetta - "Damage +25%" - li' dentro
    diventa una specifica di formato senza argomenti, e l'eccezione parte dal
    logger stesso, fuori da ogni try/catch del Translator.

    MainOptions:addModOptionsPanel costruisce le opzioni di **tutte** le mod in
    un unico giro (MainOptions.lua:2806-3010), quindi quell'unica etichetta
    porta giu' l'intera pagina Mods, quella di tutti. Noi in quel giro ci
    siamo, perche' addModOptionsPanel lo avvolgiamo per arrotondare i nostri
    quadratini di colore: cosi' il rapporto d'errore automatico finisce per
    nominare "NeatUI XP Drop" per un'etichetta di qualcun altro.

    Qui le etichette si **guardano soltanto**: si cerca il '%' isolato nella
    stringa, senza mai chiamare getText. La 1.5.1 invece le provava una per una
    con pcall(getText), e quella prova *e' lei stessa* la chiamata che esplode:
    il pcall evitava il crash, ma l'eccezione era gia' finita nel log e il
    gioco apriva il popup d'errore - ad ogni ResetLua, quindi ad ogni ingresso
    su un server, col nostro nome sopra. (lezione 28)
]]

-- Un '%' che non fa parte di un '%%': e' quello che String.format legge come
-- specifica di formato e che, senza argomenti, alza l'eccezione.
local function hasLonePercent(s)
    local i = 1
    while true do
        local at = string.find(s, "%", i, true)
        if not at then return false end
        if string.sub(s, at + 1, at + 1) ~= "%" then return true end
        i = at + 2
    end
end

-- nil = campo assente, va bene cosi'. Non-stringa = getText non la digerisce.
local function isSafeLabel(value)
    if value == nil then return true end
    if type(value) ~= "string" then return false end
    return not hasLonePercent(value)
end

-- Anche cio' che scriviamo nel log, e cio' con cui sostituiamo un'etichetta,
-- deve essere a prova di formattatore: altrimenti si sposta la bomba, non la
-- si toglie.
local function plain(value)
    return (string.gsub(tostring(value), "%%", ""))
end

--[[ Quali campi il pannello vanilla passa davvero a getText, tipo per tipo
     (MainOptions.lua:2806-3010). Fuori da questo elenco non si tocca niente:
     il tooltip di una combobox, per dire, non lo legge nessuno - toglierlo
     sarebbe un danno gratuito a casa d'altri. ]]
local GETTEXT_FIELDS = {
    title           = { name = true },
    separator       = {},
    description     = {},   -- il testo e' gia' tradotto alla registrazione
    tickbox         = { name = true, tooltip = true },
    multipletickbox = { name = true, tooltip = true },
    textentry       = { name = true, tooltip = true },
    combobox        = { name = true },
    colorpicker     = { name = true, tooltip = true },
    button          = { name = true, tooltip = true },
    keybind         = { name = true, tooltip = true },
}
local UNKNOWN_TYPE = { name = true, tooltip = true }

local function report(text)
    print("[NeatUI XP Drop] Options > Mods: " .. text)
end

local function sanitizeModOptionLabels()
    local data = PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.Data
    if type(data) ~= "table" then return end

    for _, options in ipairs(data) do
        local modName = plain(options.modOptionsID or options.name or "?")

        if not isSafeLabel(options.name) then
            report("the section title of '" .. modName .. "' holds a bare '%'."
                .. " getText() crashes on those and takes the whole Mods page"
                .. " down, so it was replaced with the mod id.")
            options.name = plain(options.modOptionsID or "Mod")
        end

        for _, option in ipairs(options.data or {}) do
            local fields = (type(option.type) == "string"
                and GETTEXT_FIELDS[option.type]) or UNKNOWN_TYPE
            local id = plain(option.id or option.type or "?")

            if fields.tooltip and not isSafeLabel(option.tooltip) then
                report("the tooltip of '" .. id .. "' (mod: " .. modName
                    .. ") holds a bare '%'. getText() crashes on those, so the"
                    .. " tooltip was dropped to keep the page alive.")
                option.tooltip = nil
            end
            if fields.name and not isSafeLabel(option.name) then
                report("the label of '" .. id .. "' (mod: " .. modName
                    .. ") holds a bare '%'. getText() crashes on those, so the"
                    .. " option id is shown instead.")
                option.name = id
            end
        end
    end
end

local _panelHooked = false
local function hookOptionsPanel()
    if _panelHooked then return end
    if not (MainOptions and MainOptions.addModOptionsPanel) then return end
    _panelHooked = true

    local vanilla = MainOptions.addModOptionsPanel
    MainOptions.addModOptionsPanel = function(self, ...)
        -- Prima di costruire, non dopo: dopo sarebbe gia' esplosa.
        pcall(sanitizeModOptionLabels)

        local result = { vanilla(self, ...) }
        local options = getOptions()
        if options then
            for optionId in pairs(COLOR_OPTIONS) do
                local opt = options:getOption(optionId)
                if opt and opt.element then
                    pcall(function() NeatXPStyle.styleSwatchButton(opt.element) end)
                end
            end
        end
        return unpack(result)
    end
end

local _hooked = false
local function hookColorPicker()
    if _hooked then return end
    if not (MainOptions and MainOptions.onModColorPick) then return end
    _hooked = true

    local vanilla = MainOptions.onModColorPick
    MainOptions.onModColorPick = function(self, button, ...)
        local id = button and button.optionID
        if type(id) == "string" and string.sub(id, 1, #PREFIX) == PREFIX then
            NeatXPSettings.openNeatPicker(self, button)
            return
        end
        return vanilla(self, button, ...)
    end
end

-- =============================================================================
-- Registration
-- =============================================================================

local function register()
    if not (PZAPI and PZAPI.ModOptions) then return end

    local options = PZAPI.ModOptions:create(NeatXPSettings.MOD_ID, NeatXPSettings.MOD_TITLE)

    -- Appearance first, then the two housekeeping controls. The mod name is
    -- already drawn as the section header by MainOptions:addModOptionsPanel,
    -- so this title only carries the subsection.
    options:addTitle("IGUI_NeatXP_Opt_Section_Colors")

    local d = NeatXPStyle.DEFAULTS
    options:addColorPicker("barColorStart", "IGUI_NeatXP_Opt_BarStart",
        d.barStart.r, d.barStart.g, d.barStart.b, 1, "IGUI_NeatXP_Opt_BarStart_Tooltip")
    options:addColorPicker("barColorEnd", "IGUI_NeatXP_Opt_BarEnd",
        d.barEnd.r, d.barEnd.g, d.barEnd.b, 1, "IGUI_NeatXP_Opt_BarEnd_Tooltip")
    options:addColorPicker("textColor", "IGUI_NeatXP_Opt_TextColor",
        d.text.r, d.text.g, d.text.b, 1, "IGUI_NeatXP_Opt_TextColor_Tooltip")

    options:addSeparator()

    options:addButton(
        "resetPos",
        "IGUI_NeatXP_ResetPos",
        "IGUI_NeatXP_Opt_ResetPos_Tooltip",
        function() NeatXPSettings.resetPosition() end,
        nil
    )

    options:addTickBox(
        "hideMod",
        "IGUI_NeatXP_Opt_HideMod",
        false,
        "IGUI_NeatXP_Opt_HideMod_Tooltip"
    )

    options:addTickBox(
        "autoHide",
        "IGUI_NeatXP_Opt_AutoHide",
        false,
        "IGUI_NeatXP_Opt_AutoHide_Tooltip"
    )

    options:addTickBox(
        "stackPanels",
        "IGUI_NeatXP_Opt_Stack",
        false,
        "IGUI_NeatXP_Opt_Stack_Tooltip"
    )

    options:addTickBox(
        "stackAbove",
        "IGUI_NeatXP_Opt_StackAbove",
        false,
        "IGUI_NeatXP_Opt_StackAbove_Tooltip"
    )

    options:addTickBox(
        "dropDown",
        "IGUI_NeatXP_Opt_DropDown",
        false,
        "IGUI_NeatXP_Opt_DropDown_Tooltip"
    )

    options:addTickBox(
        "dropOverPlayer",
        "IGUI_NeatXP_Opt_OverPlayer",
        false,
        "IGUI_NeatXP_Opt_OverPlayer_Tooltip"
    )

    local dropSize = options:addComboBox(
        "dropSize",
        "IGUI_NeatXP_Opt_DropSize",
        "IGUI_NeatXP_Opt_DropSize_Tooltip"
    )
    dropSize:addItem("IGUI_NeatXP_Opt_DropSize_Small", false)
    dropSize:addItem("IGUI_NeatXP_Opt_DropSize_Normal", true)
    dropSize:addItem("IGUI_NeatXP_Opt_DropSize_Large", false)
    dropSize:addItem("IGUI_NeatXP_Opt_DropSize_Huge", false)

    options:addTickBox(
        "replaceVanillaXp",
        "IGUI_NeatXP_Opt_ReplaceVanillaXp",
        true,
        "IGUI_NeatXP_Opt_ReplaceVanillaXp_Tooltip"
    )

    if type(PZAPI.ModOptions.load) == "function" then
        pcall(function() PZAPI.ModOptions:load() end)
        _loaded = true
    end

    -- Hide toggle
    local hideOpt = options:getOption("hideMod")
    if hideOpt then
        hideOpt.onChange      = function(_, v) fireHidden(toBool(v)) end
        hideOpt.onChangeApply = function(_, v) fireHidden(toBool(v)) end
    end

    local autoOpt = options:getOption("autoHide")
    if autoOpt then
        autoOpt.onChange      = function(_, v) fireAutoHide(toBool(v)) end
        autoOpt.onChangeApply = function(_, v) fireAutoHide(toBool(v)) end
    end

    -- Questa tocca un'impostazione del gioco, quindi va applicata subito in
    -- tutti e due i versi: accendendola spegne gli XP di lavorazione di
    -- vanilla, spegnendola glieli restituisce.
    local replaceOpt = options:getOption("replaceVanillaXp")
    if replaceOpt then
        replaceOpt.onChange      = function(_, v) NeatXPSettings.applyCraftingXp(toBool(v)) end
        replaceOpt.onChangeApply = function(_, v) NeatXPSettings.applyCraftingXp(toBool(v)) end
    end

    local sizeOpt = options:getOption("dropSize")
    if sizeOpt then
        sizeOpt.onChange      = function(_, v) applyDropSize(v) end
        sizeOpt.onChangeApply = function(_, v) applyDropSize(v) end
    end
    applyDropSize()

    -- Colours: apply the stored value now, then on every live change.
    for optionId, meta in pairs(COLOR_OPTIONS) do
        local opt = options:getOption(optionId)
        if opt then
            opt.onChange      = function(_, v) applyColor(meta.key, v) end
            opt.onChangeApply = function(_, v) applyColor(meta.key, v) end
            applyColor(meta.key, opt:getValue())
        end
    end

    hookColorPicker()
    hookOptionsPanel()
    fireHidden(NeatXPSettings.isHidden())
    fireAutoHide(NeatXPSettings.isAutoHide())
    NeatXPSettings.applyCraftingXp(NeatXPSettings.isReplaceVanillaXp())
end

-- The bar only exists in-game; from the main menu this is a no-op.
function NeatXPSettings.resetPosition()
    local bar = NeatXPDrops and NeatXPDrops.bar
    if bar and bar.resetPosition then bar:resetPosition() end
end

-- MainOptions:create() bakes the swatch button's click handler in as a function
-- *value*, so the wrapper has to be in place before the options screen is built.
-- Mod Lua loads after the base game's, so this normally lands right here; the
-- call in register() is the retry for load orders where it does not.
hookColorPicker()
hookOptionsPanel()

Events.OnGameBoot.Add(register)
