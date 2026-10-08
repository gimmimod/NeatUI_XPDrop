--[[ ============================================================================
    NeatXPConfig - config window: skills grouped by category, icon + on/off
                   switch, plus the size/position lock

    "Reset position" now lives in Options > Mods > NeatUI XP Drop; the bar's
    header no longer carries a hamburger button, so right-click is the only way
    to reach this menu.
============================================================================ ]]--

require "ISUI/ISPanel"
require "NeatXPDrops/NeatXPStyle"

local FONT_SMALL  = UIFont.Small
local FONT_MEDIUM = UIFont.Medium

-- =============================================================================
-- NeatXPConfig
-- =============================================================================
NeatXPConfig = ISPanel:derive("NeatXPConfig")

--- Le categorie da mostrare: quelle del gioco, poi - solo se c'e' - una
--- sezione sola con tutte le abilita' aggiunte da altre mod.
---
--- Vengono tolte dalle loro categorie e raccolte in fondo apposta. Sparse fra
--- le nostre sembrerebbero abilita' che abbiamo dimenticato di disegnare;
--- raccolte, si legge cosa sono: roba di qualcun altro, che seguiamo lo stesso.
--- La sezione non compare se non c'e' niente da metterci dentro.
local function displayCategories(bar)
    local out, foreign = {}, {}

    for _, cat in ipairs(bar.categories) do
        local mine = {}
        for _, skill in ipairs(cat.skills) do
            if NeatXPStyle.isForeignSkill(skill) then
                foreign[#foreign + 1] = skill
            else
                mine[#mine + 1] = skill
            end
        end
        if #mine > 0 then
            out[#out + 1] = { id = cat.id, name = cat.name, skills = mine }
        end
    end

    if #foreign > 0 then
        out[#out + 1] = {
            id = "__foreign",
            name = NeatXPStyle.tr("IGUI_NeatXP_OtherMods", "From other mods"),
            skills = foreign,
            foreign = true,
        }
    end

    return out
end

function NeatXPConfig:new(bar)
    local fhMed = getTextManager():getFontHeight(FONT_MEDIUM)
    local fhSml = getTextManager():getFontHeight(FONT_SMALL)

    local pad      = 12
    local iconS    = 30
    local switchW  = 38
    local switchH  = 19
    local cellW    = iconS + 8 + switchW + 14
    local rowH     = 40
    local headH    = fhSml + 10          -- category header strip

    local titleH  = fhMed + 16
    local footerH = fhMed + 26

    -- Pick the narrowest column count whose window still fits the screen: the
    -- grouped list is taller than the old flat grid, and B42 users run
    -- everything from 720p upwards.
    local screenH = getCore():getScreenHeight()
    local cats = displayCategories(bar)
    local cols, rowsTotal = 4, 0
    for _, c in ipairs({ 4, 5, 6, 7, 8 }) do
        cols = c
        rowsTotal = 0
        for _, cat in ipairs(cats) do
            rowsTotal = rowsTotal + math.ceil(#cat.skills / c)
        end
        local hTry = titleH + pad + #cats * headH + rowsTotal * rowH + pad + footerH
        if hTry <= screenH * 0.9 then break end
    end

    -- Footer: [All][None][Lock] ......... [Close]
    local btnH   = fhMed + 10
    local labels = {
        all   = NeatXPStyle.tr("IGUI_NeatXP_All", "All"),
        none  = NeatXPStyle.tr("IGUI_NeatXP_None", "None"),
    }
    local function btnW(label, extra)
        return math.max(72, getTextManager():MeasureStringX(FONT_SMALL, label) + 24 + (extra or 0))
    end
    local wAll   = btnW(labels.all)
    local wNone  = btnW(labels.none)
    -- Quadrato e senza scritta: il lucchetto si spiega da solo, e cosi' ha
    -- la stessa forma dei tasti quadrati delle altre due mod.
    local wLock  = btnH

    local listTop = titleH + pad
    -- Il piede: [Tutte][Nessuna]  [occhio][lucchetto]. I due quadrati stanno
    -- a destra, come i tasti quadrati nell'intestazione di Equipment.
    local footerMin = pad + wAll + 8 + wNone + 24 + btnH * 2 + 8 + pad
    local w = math.max(pad + cols * cellW + pad, footerMin)

    -- L'altezza che la lista vorrebbe, e quella che puo' avere.
    --
    -- Prima si prendeva la prima e basta: se nemmeno a otto colonne il contenuto
    -- ci stava - e con le abilita' di altre mod succede - la finestra nasceva
    -- piu' alta dello schermo, `y` finiva a zero e le ultime sezioni **e il
    -- piede** restavano fuori. Le abilita' c'erano, erano solo irraggiungibili:
    -- e' il "non riesco ad accenderla" segnalato.
    local wantH = listTop + #cats * headH + rowsTotal * rowH + pad + footerH
    local h = math.min(wantH, math.floor(screenH * 0.9))

    local o = ISPanel:new(
        math.floor((getCore():getScreenWidth() - w) / 2),
        math.max(0, math.floor((screenH - h) / 2)),
        w, h)
    setmetatable(o, self)
    self.__index = self

    o.bar = bar
    o.pad = pad
    o.iconS = iconS
    o.switchW = switchW
    o.switchH = switchH
    o.rowH = rowH
    o.headH = headH
    o.titleH = titleH
    o.footerH = footerH
    o.listTop = listTop
    o.moveWithMouse = true
    o.background = false
    o.closeSize = math.floor(fhMed)   -- NR_Config.buttonSize

    -- Lay out one block per category: a header strip, then its skills.
    -- Le coordinate sono quelle del contenuto, non dello schermo: lo
    -- scorrimento le sposta al momento di disegnarle e di cliccarle.
    o.cells = {}
    o.headers = {}
    local y = listTop + 4
    for _, cat in ipairs(cats) do
        table.insert(o.headers, { name = cat.name, skills = cat.skills,
                                  x = pad, y = y, w = w - pad * 2, h = headH })
        y = y + headH
        for i, skill in ipairs(cat.skills) do
            local perk = bar:getPerk(skill)
            local name = perk and perk:getName() or skill
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            table.insert(o.cells, { skill = skill, name = name, foreign = cat.foreign,
                                    x = pad + col * cellW, y = y + row * rowH,
                                    w = cellW - 4, h = rowH })
        end
        y = y + math.ceil(#cat.skills / cols) * rowH
    end

    -- Il riepilogo aperto col tasto destro, e a che altezza aprirlo. La
    -- finestra viene riusata fra un'apertura e l'altra, quindi si azzera anche
    -- alla chiusura.
    o.infoSkill = nil
    o.infoY = nil

    -- Quanto contenuto c'e', quanto se ne vede, e quanto si puo' scorrere.
    o.scrollY = 0
    o.contentBottom = y + 4
    o.viewTop = listTop
    o.viewBottom = h - footerH
    o.scrollMax = math.max(0, o.contentBottom - o.viewBottom)

    local by = h - footerH + 10
    o.btnAll   = { x = pad,                        y = by, w = wAll,   h = btnH, label = labels.all }
    o.btnNone  = { x = pad + wAll + 8,             y = by, w = wNone,  h = btnH, label = labels.none }
    -- Ancorati al bordo destro, non alla fine dei due tasti di sinistra:
    -- cosi' restano al loro posto qualunque sia la larghezza del pannello.
    o.btnLock  = { x = w - pad - btnH,          y = by, w = btnH, h = btnH,
                   tip = NeatXPStyle.tr("IGUI_NeatXP_Lock", "Lock") }
    o.btnHide  = { x = w - pad - btnH * 2 - 8,  y = by, w = btnH, h = btnH,
                   tip = NeatXPStyle.tr("IGUI_NeatXP_Hide", "Hide") }

    return o
end

function NeatXPConfig:initialise() ISPanel.initialise(self) end

-- Rocco header anatomy: [title] ... [red X close] (NI_SquareButton, activeColor 0.8,0.2,0.2)
function NeatXPConfig:createChildren()
    ISPanel.createChildren(self)
    local bsz = self.closeSize
    local bx = self.width - self.pad - bsz
    local by = math.floor((self.titleH - bsz) / 2)
    local icon = getTexture("media/ui/NeatUI/ICON/Icon_False.png")
    local SB = rawget(_G, "NI_SquareButton")
    if SB then
        self.closeButton = SB:new(bx, by, bsz, icon, self, function() self:close() end)
        self.closeButton:initialise()
        self.closeButton:setActive(true)
        self.closeButton:setActiveColor(0.8, 0.2, 0.2)
        self:addChild(self.closeButton)
    else
        self.btnX = { x = bx, y = by, w = bsz, h = bsz, icon = icon }
    end
end

local function inRect(mx, my, r)
    return mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

-- A category counts as "on" only when every one of its skills is tracked.
function NeatXPConfig:isCategoryOn(skills)
    for _, s in ipairs(skills) do
        if not self.bar:isTracked(s) then return false end
    end
    return true
end

function NeatXPConfig:prerender()
    local w, h = self.width, self.height
    local mx, my = self:getMouseX(), self:getMouseY()
    local over = self:isMouseOver()

    -- Rocco anatomy: rounded MainTitle_BG header + FlatTop body below it (opaque)
    NeatXPStyle.drawWindow(self, 0, 0, w, h, self.titleH, 1.0, 1.0)
    self:drawText(NeatXPStyle.tr("IGUI_NeatXP_ConfigTitle", "Tracked skills"), self.pad,
        math.floor((self.titleH - getTextManager():getFontHeight(FONT_MEDIUM)) / 2),
        1, 1, 1, 1, FONT_MEDIUM)

    -- inner list panel
    local listBot = h - self.footerH
    NeatXPStyle.drawNP(self, NeatXPStyle.TEX.innerPanel, self.pad, self.listTop,
        w - self.pad * 2, listBot - self.listTop, 0.16, 0.93)

    -- La lista scorre: tutto quello che segue e' ritagliato dentro il riquadro
    -- e spostato di -scrollY. Le coordinate salvate restano quelle del
    -- contenuto, cosi' misura e clic parlano la stessa lingua.
    local acc = NeatXPStyle.accent
    local fhS = getTextManager():getFontHeight(FONT_SMALL)
    local sy0 = self.scrollY
    self:setStencilRect(self.pad, self.viewTop, w - self.pad * 2, self.viewBottom - self.viewTop)

    -- category headers (clicking one toggles the whole group)
    for _, head in ipairs(self.headers) do
        local y = head.y - sy0
        local hover = over and inRect(mx, my + sy0, head)
        if hover then self:drawRect(head.x, y, head.w, head.h, 0.10, 1, 1, 1) end
        self:drawText(head.name, head.x + 6, y + math.floor((head.h - fhS) / 2),
            acc.r, acc.g, acc.b, hover and 1 or 0.9, FONT_SMALL)
        self:drawRect(head.x + 6, y + head.h - 1, head.w - 12, 1, 0.25, 1, 1, 1)
    end

    -- rows: icon + switch
    local hoveredName = nil
    local brush = NeatXPStyle.brushIcon()
    for _, c in ipairs(self.cells) do
        local y = c.y - sy0
        local hover = over and inRect(mx, my + sy0, c)
        if hover then
            self:drawRect(c.x + 2, y, c.w - 4, c.h, 0.10, 1, 1, 1)
            hoveredName = c.name
        end
        local tracked = self.bar:isTracked(c.skill)
        local ix = c.x + 6
        local iy = y + math.floor((c.h - self.iconS) / 2)
        local alpha = tracked and 1 or 0.45
        if c.foreign then
            -- L'icona sua se sappiamo trovarla, il pennello altrimenti. Il
            -- pennello sta qui e solo qui: serve perche' la riga abbia
            -- comunque qualcosa accanto all'interruttore.
            local own = NeatXPStyle.getSkillIcon(c.skill)
            local tex = own or brush
            if tex then
                self:drawTextureScaled(tex, ix, iy, self.iconS, self.iconS, alpha, 1, 1, 1)
            end
        else
            NeatXPStyle.drawIcon(self, ix, iy, self.iconS, c.skill, c.name, alpha)
        end
        local sx = ix + self.iconS + 8
        NeatXPStyle.drawSwitch(self, sx, y + math.floor((c.h - self.switchH) / 2),
            self.switchW, self.switchH, tracked)
    end

    self:clearStencilRect()

    -- Il riepilogo di un'abilita', se ne e' stata chiesta una col tasto destro.
    -- Dopo lo stencil, o verrebbe tagliato insieme alla lista.
    if self.infoSkill then self:renderSkillInfo(mx, my, over) end

    -- La barretta di scorrimento: si vede solo se c'e' qualcosa da scorrere.
    if self.scrollMax > 0 then
        local trackX = w - self.pad - 4
        local trackY = self.viewTop + 2
        local trackH = self.viewBottom - self.viewTop - 4
        local viewH = self.viewBottom - self.viewTop
        local knobH = math.max(20, math.floor(trackH * viewH / (viewH + self.scrollMax)))
        local knobY = trackY + math.floor((trackH - knobH) * (sy0 / self.scrollMax))
        self:drawRect(trackX, trackY, 3, trackH, 0.18, 1, 1, 1)
        self:drawRect(trackX, knobY, 3, knobH, 0.55, acc.r, acc.g, acc.b)
    end

    -- fallback close X (only when NI_SquareButton is unavailable)
    if self.btnX then
        local bxHover = over and inRect(mx, my, self.btnX)
        local cr = { r = 0.8, g = 0.2, b = 0.2 }   -- NeatUI close red
        if bxHover then cr = { r = math.min(0.8 * 1.2, 1), g = 0.24, b = 0.24 } end
        local bgT = getTexture("media/ui/NeatUI/Button/Background.png")
        if bgT then
            self:drawTextureScaled(bgT, self.btnX.x, self.btnX.y, self.btnX.w, self.btnX.h, 0.8, cr.r, cr.g, cr.b)
        else
            self:drawRect(self.btnX.x, self.btnX.y, self.btnX.w, self.btnX.h, 0.8, cr.r, cr.g, cr.b)
        end
        if self.btnX.icon then
            local isz = math.floor(self.btnX.w * 0.8)
            local io_ = math.floor((self.btnX.w - isz) / 2)
            self:drawTextureScaled(self.btnX.icon, self.btnX.x + io_, self.btnX.y + io_, isz, isz, 1, 1, 1, 1)
        end
    end

    -- hovered skill name in the title bar (right side, clear of the X button)
    if hoveredName then
        self:drawTextRight(hoveredName, w - self.pad * 2 - self.closeSize,
            math.floor((self.titleH - fhS) / 2),
            acc.r, acc.g, acc.b, 1, FONT_SMALL)
    end

    -- footer buttons
    for _, b in ipairs({ self.btnAll, self.btnNone }) do
        local hover = over and inRect(mx, my, b)
        NeatXPStyle.drawButton(self, b.x, b.y, b.w, b.h, hover and "hover" or nil)
        self:drawTextCentre(b.label, b.x + math.floor(b.w / 2),
            b.y + math.floor((b.h - fhS) / 2),
            1, 1, 1, 1, FONT_SMALL)
    end

    -- L'occhio: nasconde la barra, che si ripiega nella pastiglia XP. Non si
    -- accende mai di arancione - l'arancione qui vuol dire "impostazione
    -- lasciata attiva", e questa e' una cosa che si fa, non uno stato.
    local hb = self.btnHide
    local hideHover = over and inRect(mx, my, hb)
    NeatXPStyle.drawSquareButton(self, hb.x, hb.y, hb.h,
        NeatXPStyle.hideIcon(), { r = 0.20, g = 0.20, b = 0.20 }, hideHover)

    -- lock: latching button, orange while the panel is pinned
    local lb = self.btnLock
    local locked = self.bar:isLocked()
    local lockHover = over and inRect(mx, my, lb)
    -- Composto come il tasto quadrato di CleanUI: arancione pieno quando e'
    -- bloccato, grigio quando non lo e'. Sono i suoi stessi colori.
    local color = locked and { r = 0.95, g = 0.50, b = 0.10 }
                          or { r = 0.20, g = 0.20, b = 0.20 }
    NeatXPStyle.drawSquareButton(self, lb.x, lb.y, lb.h,
        NeatXPStyle.lockIcon(locked), color, lockHover)
end

--[[ Il riepilogo di un'abilita' dentro la finestra di configurazione.

    Stesse righe del riepilogo che compare passando il mouse sul pannello, e
    stessi numeri: li chiede tutti e due alla barra (`skillStats`, `boostInfo`),
    cosi' non possono raccontare due storie diverse.

    Serve a una cosa sola, ed e' quella chiesta: guardare a che punto sono
    **tutte** le abilita' e dove ci sono i moltiplicatori attivi, senza aprire
    la schermata del personaggio.
]]
function NeatXPConfig:renderSkillInfo(mx, my, over)
    local bar = self.bar
    local skill = self.infoSkill
    local perk = bar:getPerk(skill)
    if not perk then self.infoSkill = nil; return end

    local font, fh = FONT_SMALL, getTextManager():getFontHeight(FONT_SMALL)
    local pad = 10
    local headerH = fh + 8

    local level, cur, max, pct = bar:skillStats(skill)
    local rate, multiplied = bar:boostInfo(perk)

    local remaining = math.max(0, max - cur)
    local rows = {
        { NeatXPStyle.tr("IGUI_NeatXP_Current", "Current:"),      string.format("%.1f", cur) },
        { NeatXPStyle.tr("IGUI_NeatXP_NextLevel", "Next level:"), string.format("%.0f", max) },
        { NeatXPStyle.tr("IGUI_NeatXP_Remaining", "Remaining:"),  string.format("%.1f", remaining) },
        { NeatXPStyle.tr("IGUI_NeatXP_Progress", "Progress:"),    tostring(math.floor(pct * 100)) .. "%" },
    }

    local bw = math.max(200, math.floor(self.width * 0.7))
    local bh = headerH + 6 + (#rows + (rate and 1 or 0)) * (fh + 2) + 8

    -- Centrato nella finestra e tenuto dentro la zona della lista: cosi' non
    -- esce mai dal pannello, qualunque riga sia stata cliccata.
    local bx = math.floor((self.width - bw) / 2)
    local by = math.max(self.viewTop + 4,
        math.min(self.infoY or self.viewTop, self.viewBottom - bh - 4))

    NeatXPStyle.drawWindow(self, bx, by, bw, bh, headerH, 1.0, 1.0)

    local acc = NeatXPStyle.accent
    local tr, tg, tb = NeatXPStyle.getColor("text")
    local hy = by + math.floor((headerH - fh) / 2)
    self:drawText(perk:getName(), bx + pad, hy, acc.r, acc.g, acc.b, 1, font)
    self:drawTextRight(NeatXPStyle.tr("IGUI_NeatXP_Level", "Lv") .. " " .. tostring(level),
        bx + bw - pad, hy, tr, tg, tb, 1, font)

    local py = by + headerH + 5
    for i, row in ipairs(rows) do
        local ry = py + (i - 1) * (fh + 2)
        self:drawText(row[1], bx + pad, ry, 1, 1, 1, NeatXPStyle.textDim, font)
        self:drawTextRight(row[2], bx + bw - pad, ry, tr, tg, tb, 1, font)
    end

    if rate then
        local ry = py + #rows * (fh + 2)
        self:drawText(NeatXPStyle.tr("IGUI_NeatXP_XpRate", "XP rate:"),
            bx + pad, ry, 1, 1, 1, NeatXPStyle.textDim, font)
        self:drawTextRight(rate, bx + bw - pad, ry, acc.r, acc.g, acc.b, 1, font)
        if multiplied then
            local arrow = NeatXPStyle.arrowUpIcon()
            local rw = getTextManager():MeasureStringX(font, rate)
            if arrow then
                self:drawTextureScaled(arrow, bx + bw - pad - rw - fh - 2, ry, fh, fh,
                    1, acc.r, acc.g, acc.b)
            end
        end
    end
end

--- Tasto destro su un'abilita': apre il suo riepilogo, o lo chiude se era gia'
--- quello. Fuori dalle righe, chiude e basta.
function NeatXPConfig:onRightMouseDown(x, y)
    if y >= self.viewTop and y < self.viewBottom then
        local cy = y + self.scrollY
        for _, c in ipairs(self.cells) do
            if inRect(x, cy, c) then
                self.infoSkill = (self.infoSkill ~= c.skill) and c.skill or nil
                self.infoY = c.y - self.scrollY
                return true
            end
        end
    end
    self.infoSkill = nil
    return true
end

function NeatXPConfig:onMouseDown(x, y)
    if self.btnX and inRect(x, y, self.btnX) then self:close(); return true end
    if self.btnHide and inRect(x, y, self.btnHide) then
        -- Nascondere la barra mentre la sua configurazione resta aperta davanti
        -- sarebbe una contraddizione: si chiude anche questa.
        self.bar:setCollapsed(true)
        self:close()
        return true
    end
    if inRect(x, y, self.btnLock) then
        self.bar:toggleLocked()
        return true
    end
    if inRect(x, y, self.btnAll) then
        for _, s in ipairs(self.bar.skillOrder) do self.bar:setTracked(s, true) end
        return true
    end
    if inRect(x, y, self.btnNone) then
        for _, s in ipairs(self.bar.skillOrder) do self.bar:setTracked(s, false) end
        return true
    end
    -- Dentro la lista si ragiona in coordinate del contenuto: il clic scende di
    -- quanto la lista e' salita. E un clic fuori dal riquadro non conta, o si
    -- accenderebbe una riga scorsa via sotto il piede.
    if y >= self.viewTop and y < self.viewBottom then
        local cy = y + self.scrollY
        for _, head in ipairs(self.headers) do
            if inRect(x, cy, head) then
                local turnOn = not self:isCategoryOn(head.skills)
                for _, s in ipairs(head.skills) do self.bar:setTracked(s, turnOn) end
                return true
            end
        end
        for _, c in ipairs(self.cells) do
            if inRect(x, cy, c) then
                self.bar:setTracked(c.skill, not self.bar:isTracked(c.skill))
                return true
            end
        end
    end
    ISPanel.onMouseDown(self, x, y)
    return true
end

--- La rotella scorre la lista. Restituisce true solo quando c'e' davvero da
--- scorrere: altrimenti la rotella resta di chi sta sotto.
function NeatXPConfig:onMouseWheel(del)
    if self.scrollMax <= 0 then return false end
    self.scrollY = math.max(0, math.min(self.scrollMax, self.scrollY + del * self.rowH))
    return true
end

function NeatXPConfig:close()
    self.bar:writeConfig()
    self.infoSkill = nil
    self:setVisible(false)
    self:removeFromUIManager()
end

function NeatXPConfig:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE
end

function NeatXPConfig:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then self:close() end
end
