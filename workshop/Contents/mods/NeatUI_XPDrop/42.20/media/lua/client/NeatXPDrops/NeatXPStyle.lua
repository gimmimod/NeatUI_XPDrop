--[[ ============================================================================
    NeatXPStyle - NeatUI-flavoured drawing helpers for Neat XP Drops.

    Everything the bar draws goes through here so that the user-configurable
    colours (Mod Options) and the panel scale factor only have to be applied in
    one place.
============================================================================ ]]--

NeatXPStyle = NeatXPStyle or {}

-- ---- Palette ----------------------------------------------------------------
NeatXPStyle.accent      = { r = 0.95, g = 0.50, b = 0.10 }   -- NR_Config accent
NeatXPStyle.grey        = { r = 0.45, g = 0.45, b = 0.45 }
NeatXPStyle.panelTint   = 0.15   -- NR_Config.panelBg
NeatXPStyle.panelAlpha  = 0.70
NeatXPStyle.textDim     = 0.72

-- User colours (Mod Options overwrites these; defaults reproduce the 1.1 look).
NeatXPStyle.DEFAULTS = {
    barStart = { r = 0.40, g = 0.80, b = 0.42 },   -- bar at 0%
    barEnd   = { r = 0.95, g = 0.50, b = 0.10 },   -- bar at 100% (accent)
    text     = { r = 1.00, g = 1.00, b = 1.00 },   -- panel text: numbers + levels
}

NeatXPStyle.colors = {
    barStart = { r = 0.40, g = 0.80, b = 0.42 },
    barEnd   = { r = 0.95, g = 0.50, b = 0.10 },
    text     = { r = 1.00, g = 1.00, b = 1.00 },
}

function NeatXPStyle.setColor(key, r, g, b)
    local c = NeatXPStyle.colors[key]
    if c == nil then return end
    c.r = math.max(0, math.min(tonumber(r) or c.r, 1))
    c.g = math.max(0, math.min(tonumber(g) or c.g, 1))
    c.b = math.max(0, math.min(tonumber(b) or c.b, 1))
end

function NeatXPStyle.getColor(key)
    local c = NeatXPStyle.colors[key] or NeatXPStyle.DEFAULTS[key]
    return c.r, c.g, c.b
end

-- ---- Textures ---------------------------------------------------------------
NeatXPStyle.TEX = {
    panelRound = "media/ui/NeatUI/DefaultPanel/MainPanelBG_RoundTop.png",
    panelFlat  = "media/ui/NeatUI/DefaultPanel/MainPanelBG_FlatTop.png",
    titleBar   = "media/ui/NeatUI/DefaultPanel/MainTitle_BG.png",
    innerPanel = "media/ui/NeatUI/DefaultPanel/InnerPanel_BG.png",
    btnL       = "media/ui/NeatUI/Button/Button_FULL_L.png",
    btnM       = "media/ui/NeatUI/Button/Button_FULL_M.png",
    btnR       = "media/ui/NeatUI/Button/Button_FULL_R.png",
    btnBg      = "media/ui/NeatUI/Button/Background.png",
    btnBorder  = "media/ui/NeatUI/Button/Boarder.png",
    resize     = "media/ui/NeatUI/Resize/ResizeIcon.png",

    -- Il glifo XP di Rocco: la stessa immagine che sta al centro dell'icona
    -- della mod, cosi' la pastiglia ripiegata e l'icona nell'elenco mod sono
    -- riconoscibilmente la stessa cosa.
    xpGlyph    = { "media/ui/Neat_Building/ICON/Icon_XPAward.png", "media/ui/NeatXP/Icon_XPAward.png" },

    -- L'occhio di NeatUI Equipment, la stessa immagine: nascondere una cosa ha
    -- lo stesso disegno in tutte e due le mod.
    hideIcon   = { "media/ui/NeatEquipment/Icon_Eye_Hide.png", "media/ui/NeatXP/Icon_Eye_Hide.png" },

    -- Il badge della mod: lo stesso disegno dell'icona nell'elenco mod.
    badge      = { "media/ui/NeatXP/Icon_XPDrop.png" },

    -- Il tasto quadrato di CleanUI: fondo stondato che prende la tinta, piu' un
    -- contorno separato. Se CleanUI non c'e', le due dell'equivalente NeatUI.
    sqBg       = { "media/ui/CleanUI/Button/SQBackground.png", "media/ui/NeatUI/Button/Background.png" },
    sqBorder   = { "media/ui/CleanUI/Button/SQBorder.png",     "media/ui/NeatUI/Button/Boarder.png" },
    barL       = "media/ui/NeatXP/bar_l.png",
    barM       = "media/ui/NeatXP/bar_m.png",
    barR       = "media/ui/NeatXP/bar_r.png",
    switchOn   = "media/ui/NeatXP/switch_on.png",
    switchOff  = "media/ui/NeatXP/switch_off.png",
    lockOn     = { "media/ui/CleanUI/ICON/Icon_Lock.png",   "media/ui/NeatXP/lock_on.png" },
    lockOff    = { "media/ui/CleanUI/ICON/Icon_UnLock.png", "media/ui/NeatXP/lock_off.png" },

    -- I due chevron di Rocco. In su: l'abilita' sta guadagnando XP moltiplicati,
    -- o un valore e' salito. In giu': un valore e' sceso. Sono bianchi su
    -- trasparente, quindi si tingono come il resto.
    arrowUp    = { "media/ui/NeatRocco/ICON/Icon_ArrowUp.png",   "media/ui/NeatXP/Icon_ArrowUp.png" },
    arrowDown  = { "media/ui/NeatRocco/ICON/Icon_ArrowDown.png", "media/ui/NeatXP/Icon_ArrowDown.png" },
}

--[[ Verde e rosso degli avvisi sopra la testa. Sono nostri, e sono due costanti.

    Il significato sta nel colore: la noia che sale e' una brutta notizia, la
    felicita' che sale e' una buona. Quella distinzione la manteniamo - e' la
    regola di vanilla, ricopiata in NeatXPSettings.

    **La sfumatura esatta invece non la chiediamo al motore, e la prima versione
    lo faceva.** `HaloTextHelper.getGoodColor()` esiste - lo chiama
    `ISRadioInteractions.lua:312` - ma l'oggetto che restituisce non risponde a
    `getR()`, e in Kahlua chiamare un valore nullo non e' un errore che `pcall`
    converte in `false`: e' un'eccezione Java che sale lo stesso, a ogni
    fotogramma (lezione 33). Il `pcall` che avevo messo attorno "per sicurezza"
    non ha trattenuto niente e ha solo nascosto dove guardare.

    Si potrebbe passare da `getCore():getGoodHighlitedColor():getR()`, che in
    vanilla Lua c'e' davvero (UnitTestsTimedActionsPanel.lua:118). Ma quello e'
    il colore di evidenziazione dell'interfaccia, non quello degli avvisi: non
    sarebbe piu' fedele, sarebbe solo un'altra chiamata al motore per ottenere
    un verde. Un verde ce l'abbiamo.
]]
local HALO_GOOD = { r = 0.30, g = 0.85, b = 0.30 }
local HALO_BAD  = { r = 0.85, g = 0.25, b = 0.25 }

--- Il colore di un avviso sopra la testa: verde se e' una buona notizia.
function NeatXPStyle.haloColor(good)
    return good and HALO_GOOD or HALO_BAD
end

local _tex = {}
local function tex(path)
    if _tex[path] == nil then _tex[path] = getTexture(path) or false end
    if _tex[path] == false then return nil end
    return _tex[path]
end
NeatXPStyle.tex = tex

-- ---- Font ladder ------------------------------------------------------------
-- The panel is resizable, so every text has to pick the largest bundled font
-- that still fits the box it is drawn in. Built lazily: UIFont is a Java enum
-- and not every build exposes the same members.
local _ladder = nil

local function buildLadder()
    local tm = getTextManager()
    local seen, out = {}, {}
    for _, name in ipairs({ "Small", "NewSmall", "Medium", "NewMedium", "Large", "NewLarge" }) do
        local ok, font = pcall(function() return UIFont[name] end)
        if ok and font ~= nil then
            local ok2, h = pcall(function() return tm:getFontHeight(font) end)
            if ok2 and type(h) == "number" and h > 0 and not seen[h] then
                seen[h] = true
                table.insert(out, { font = font, h = h })
            end
        end
    end
    if #out == 0 then out = { { font = UIFont.Small, h = tm:getFontHeight(UIFont.Small) } } end
    table.sort(out, function(a, b) return a.h < b.h end)
    return out
end

-- Largest font whose height fits maxH (never smaller than the smallest bundled
-- font, so text degrades by clipping rather than vanishing).
function NeatXPStyle.pickFont(maxH)
    if _ladder == nil then _ladder = buildLadder() end
    local chosen = _ladder[1]
    for _, e in ipairs(_ladder) do
        if e.h <= maxH then chosen = e else break end
    end
    return chosen.font, chosen.h
end

function NeatXPStyle.fontHeight(font)
    return getTextManager():getFontHeight(font)
end

-- ---- 3-slice helper (crisp caps, stretched middle) --------------------------
local function draw3(el, tl, tm, tr, x, y, w, h, capW, a, r, g, b)
    capW = math.min(capW, math.floor(w / 2))
    if capW < 1 then capW = 1 end
    el:drawTextureScaled(tl, x, y, capW, h, a, r, g, b)
    local midW = w - capW * 2
    if midW > 0 and tm then el:drawTextureScaled(tm, x + capW, y, midW, h, a, r, g, b) end
    el:drawTextureScaled(tr, x + w - capW, y, capW, h, a, r, g, b)
end

-- ---- NinePatch panel (generic) ----------------------------------------------
function NeatXPStyle.drawNP(el, path, x, y, w, h, tint, alpha)
    local np = NinePatchTexture and NinePatchTexture.getSharedTexture and NinePatchTexture.getSharedTexture(path)
    if np then
        np:render(el:getAbsoluteX() + x, el:getAbsoluteY() + y, w, h, tint, tint, tint, alpha or 0.9)
    else
        el:drawRectStatic(x, y, w, h, alpha or 0.9, tint, tint, tint)
        local g = NeatXPStyle.grey
        el:drawRectBorderStatic(x, y, w, h, 0.7, g.r, g.g, g.b)
    end
end

function NeatXPStyle.drawPanel(el, x, y, w, h, rounded, alpha)
    NeatXPStyle.drawNP(el, rounded and NeatXPStyle.TEX.panelRound or NeatXPStyle.TEX.panelFlat,
        x, y, w, h, NeatXPStyle.panelTint, alpha or NeatXPStyle.panelAlpha)
end

-- Rocco window anatomy: MainTitle_BG header (rounded top) + MainPanelBG_FlatTop
-- body drawn BELOW it. Never a full-height panel under a square strip: that is
-- what leaves square corners peeking out behind the rounded ones.
function NeatXPStyle.drawWindow(el, x, y, w, h, headerH, alphaHeader, alphaBody)
    NeatXPStyle.drawNP(el, NeatXPStyle.TEX.titleBar, x, y, w, headerH, 0.08, alphaHeader or 1.0)
    NeatXPStyle.drawNP(el, NeatXPStyle.TEX.panelFlat, x, y + headerH, w, h - headerH,
        NeatXPStyle.panelTint, alphaBody or 1.0)
    -- La riga nera sotto l'intestazione: e' quella che stacca le due tinte e
    -- da' il bordo netto. Equipment ce l'ha da sempre, queste no, ed era la
    -- differenza che si vedeva di piu' mettendo le finestre affiancate.
    el:drawRect(x, y + headerH - 1, w, 1, 1, 0, 0, 0)
end

-- ---- Button (official framework 3-slice, rounded, not stretched) ------------
function NeatXPStyle.drawButton(el, x, y, w, h, state)
    local L, M, R = tex(NeatXPStyle.TEX.btnL), tex(NeatXPStyle.TEX.btnM), tex(NeatXPStyle.TEX.btnR)
    local a = NeatXPStyle.accent
    -- Same states as NI_SquareButton (framework): default 0.2, hover 0.3, pressed 0.1, alpha 0.8.
    local r, g, b, al = 0.20, 0.20, 0.20, 0.8
    if state == "pressed" then r, g, b = 0.10, 0.10, 0.10
    elseif state == "hover" then r, g, b = 0.30, 0.30, 0.30
    elseif state == "active" then r, g, b = a.r, a.g, a.b; al = 0.8
    elseif state == "activeHover" then r, g, b = math.min(a.r * 1.2, 1), math.min(a.g * 1.2, 1), math.min(a.b * 1.2, 1); al = 0.8 end
    if L and R then
        draw3(el, L, M, R, x, y, w, h, h, al, r, g, b)
    else
        el:drawRectStatic(x, y, w, h, al, r, g, b)
        el:drawRectBorderStatic(x, y, w, h, 1, NeatXPStyle.grey.r, NeatXPStyle.grey.g, NeatXPStyle.grey.b)
    end
end

-- ---- Resize grip (framework ResizeIcon art) ---------------------------------
-- The corner-arrow grip Rocco's resizable panels use, drawn bottom-right.
--
--- Il trascinatore d'angolo: la ricetta di Neat Rocco (NR_ResizeWidget).
--- Aspetto conservato, scatola rispettata, alfa 0.6 / 0.8 come la loro.
function NeatXPStyle.drawResizeGrip(el, x, y, size, hover)
    local t = tex(NeatXPStyle.TEX.resize)
    local a = hover and 0.8 or 0.6
    if t then
        el:drawTextureScaledAspect(t, x, y, size, size, a, 1, 1, 1)
        return
    end
    -- Fallback: three stacked diagonal ticks, same silhouette as the art.
    local th = math.max(1, math.floor(size * 0.12))
    for i = 1, 3 do
        local len = math.floor(size * (0.30 + 0.22 * (i - 1)))
        local oy  = y + size - i * math.floor(size * 0.28)
        el:drawRectStatic(x + size - len, oy, len, th, a, 0.92, 0.92, 0.92)
    end
end

--[[ ---- Colour swatch ---------------------------------------------------------
    A rounded chip filled with the colour it stands for. Same recipe as NeatUI
    Hairstyler's, deliberately: the two mods sit in the same options screen.

    Background.png is the piece that takes a tint. The Button_FULL 3-slice does
    not - that art is black at low alpha (centre pixel 0,0,0 a33), shading meant
    to sit *over* something, so multiplying it by a colour just gives black.
    Background.png is white at a139, so tinting yields the colour and its own
    alpha edge keeps the corners round. One pass lands near 55% opacity and the
    panel shows through; three stack to ~91%, which reads as solid. Boarder.png
    then supplies the rounded outline, because a drawRectBorder would leave four
    bright corners hanging off a rounded chip.

    styleSwatchButton skins a vanilla ISButton in place - the caller keeps setting
    btn.backgroundColor, which is where MainOptions:addColorButton already puts the
    value. Latches, so re-opening the options screen is free.
]]
function NeatXPStyle.drawSwatch(el, x, y, w, h, r, g, b, brd)
    local bg, border = tex(NeatXPStyle.TEX.btnBg), tex(NeatXPStyle.TEX.btnBorder)
    if bg then
        for _ = 1, 3 do el:drawTextureScaled(bg, x, y, w, h, 1, r, g, b) end
    else
        el:drawRectStatic(x, y, w, h, 1, r, g, b)
    end
    if border then
        el:drawTextureScaled(border, x, y, w, h, 1, brd, brd, brd)
    else
        el:drawRectBorderStatic(x, y, w, h, 1, brd, brd, brd)
    end
end

function NeatXPStyle.styleSwatchButton(btn)
    if not btn then return end
    btn:setDisplayBackground(false)
    if btn._neatXPSwatch then return end
    btn._neatXPSwatch = true

    btn.prerender = function(b)
        local c = b.backgroundColor or { r = 1, g = 1, b = 1 }
        local brd = 0.45
        if b.pressed then brd = 0.30
        elseif b:isMouseOver() and b.enable ~= false then brd = 0.75 end
        NeatXPStyle.drawSwatch(b, 0, 0, b.width, b.height, c.r, c.g, c.b, brd)
    end
end

-- ---- Lock glyph -------------------------------------------------------------
-- lock_on / lock_off are byte-identical copies of CleanUI's Icon_Lock.png and
-- Icon_UnLock.png, bundled here because CleanUI is not a dependency and its
-- media/ui tree only exists when that mod is enabled. Copying them is the only
-- way the padlock reads *exactly* the same as the one on CleanUI's inventory
-- title bar, which is the point.
--
-- 64x64 white-on-transparent, stroked outline, silhouette at x[10..53] y[2..58];
-- NeatXPConfig sizes the draw box from those numbers. Tinted near-white like
-- NI_SquareButton does with its icons - the button's own active state supplies
-- the orange, the glyph never does.
--- Come tex(), ma su una lista: si tiene la prima che esiste. Serve per le
--- icone che preferiamo prendere da un'altra mod quando c'e' - il lucchetto di
--- CleanUI - senza restare a mani vuote quando non c'e'.
local function texAny(list)
    if type(list) == "string" then return tex(list) end
    for _, p in ipairs(list or {}) do
        local t = tex(p)
        if t then return t end
    end
    return nil
end

--[[ Il tasto quadrato di CleanUI, composto come lo compone lei.

    Da ISInventoryPage.lua (closeButton / collapseButton), nell'ordine:

      1. SQBackground tinto con il colore dello stato, alfa 1
      2. SQBorder sopra, sempre a 0.4/0.4/0.4, alfa 1
      3. l'icona all'80% del tasto, centrata, bianca piena

    Sono tre passaggi, non uno: il fondo prende il colore, il contorno resta
    grigio e non si tinge mai, l'icona sta sopra a entrambi. Disegnare l'icona
    tinta, o saltare il contorno, e' quello che faceva sembrare il nostro
    lucchetto "non identico" al loro.
]]
function NeatXPStyle.drawSquareButton(el, x, y, size, icon, color, hover)
    local bg = texAny(NeatXPStyle.TEX.sqBg)
    local br = texAny(NeatXPStyle.TEX.sqBorder)

    local r, g, b = color.r, color.g, color.b
    if hover then
        r = math.min(r * 1.15 + 0.05, 1)
        g = math.min(g * 1.15 + 0.05, 1)
        b = math.min(b * 1.15 + 0.05, 1)
    end

    if bg then el:drawTextureScaled(bg, x, y, size, size, 1, r, g, b)
    else el:drawRectStatic(x, y, size, size, 1, r, g, b) end

    if br then el:drawTextureScaled(br, x, y, size, size, 1, 0.4, 0.4, 0.4)
    else el:drawRectBorderStatic(x, y, size, size, 1, 0.4, 0.4, 0.4) end

    if icon then
        local iconSize = math.floor(size * 0.8)
        local off = math.floor((size - iconSize) / 2)
        el:drawTextureScaled(icon, x + off, y + off, iconSize, iconSize, 1, 1, 1, 1)
    end
end

--- L icona del lucchetto, aperta o chiusa. Serve al tasto quadrato, che la
--- disegna da se al posto giusto e della misura giusta.
--- Il glifo XP, per la pastiglia che resta quando il pannello e nascosto.
function NeatXPStyle.xpGlyph()
    return texAny(NeatXPStyle.TEX.xpGlyph)
end

--- Il badge della mod, per il pannello ripiegato.
function NeatXPStyle.badgeIcon()
    return texAny(NeatXPStyle.TEX.badge)
end

--- L'occhio barrato: nascondi.
function NeatXPStyle.hideIcon()
    return texAny(NeatXPStyle.TEX.hideIcon)
end

function NeatXPStyle.lockIcon(locked)
    return texAny(locked and NeatXPStyle.TEX.lockOn or NeatXPStyle.TEX.lockOff)
end

--- Il chevron in su: accanto al ritmo di guadagno quando c'e' un
--- moltiplicatore attivo.
function NeatXPStyle.arrowUpIcon()
    return texAny(NeatXPStyle.TEX.arrowUp)
end

--- Il chevron nella direzione chiesta. Non si ruota quello in su: il motore non
--- sa girare una texture, e i due disegni di Rocco esistono gia' tutti e due.
function NeatXPStyle.arrowIcon(up)
    return texAny(up and NeatXPStyle.TEX.arrowUp or NeatXPStyle.TEX.arrowDown)
end

function NeatXPStyle.drawLockGlyph(el, x, y, size, locked, alpha)
    alpha = alpha or 1.0
    local t = texAny(locked and NeatXPStyle.TEX.lockOn or NeatXPStyle.TEX.lockOff)
    if t then
        el:drawTextureScaled(t, x, y, size, size, alpha, 0.92, 0.92, 0.92)
        return
    end
    -- Fallback: blocky padlock, open variant loses the left upright.
    local bodyW = math.max(6, math.floor(size * 0.66))
    local bodyH = math.max(5, math.floor(size * 0.42))
    local bx    = x + math.floor((size - bodyW) / 2)
    local by    = y + size - bodyH - math.max(1, math.floor(size * 0.14))
    el:drawRectStatic(bx, by, bodyW, bodyH, alpha, 0.92, 0.92, 0.92)
    local th    = math.max(1, math.floor(size * 0.13))
    local archW = math.max(4, math.floor(bodyW * 0.66))
    local archX = x + math.floor((size - archW) / 2)
    local archH = math.max(3, by - y - 1)
    el:drawRectStatic(archX, by - archH, archW, th, alpha, 0.92, 0.92, 0.92)
    el:drawRectStatic(archX + archW - th, by - archH, th, archH, alpha, 0.92, 0.92, 0.92)
    if locked then
        el:drawRectStatic(archX, by - archH, th, archH, alpha, 0.92, 0.92, 0.92)
    end
end

-- ---- Toggle switch (green/red, from Rocco art) ------------------------------
function NeatXPStyle.drawSwitch(el, x, y, w, h, on)
    local t = tex(on and NeatXPStyle.TEX.switchOn or NeatXPStyle.TEX.switchOff)
    if t then
        el:drawTextureScaled(t, x, y, w, h, 1, 1, 1, 1)
    else
        if on then el:drawRectStatic(x, y, w, h, 1, 0.30, 0.70, 0.35)
        else el:drawRectStatic(x, y, w, h, 1, 0.70, 0.30, 0.30) end
    end
end

-- ---- Progress bar -----------------------------------------------------------
-- Straight lerp between the two user colours: with the 1.1 defaults (green ->
-- accent) it reads the same as the old hand-tuned three-stop ramp.
function NeatXPStyle.getFillColor(pct)
    pct = math.max(0, math.min(pct or 0, 1))
    local a, b = NeatXPStyle.colors.barStart, NeatXPStyle.colors.barEnd
    return a.r + (b.r - a.r) * pct,
           a.g + (b.g - a.g) * pct,
           a.b + (b.b - a.b) * pct
end

-- label (optional) is centred inside the bar: see NeatXPBar's compact layout.
function NeatXPStyle.drawBar(el, x, y, w, h, pct, label, labelFont)
    pct = math.max(0, math.min(pct or 0, 1))
    local L, M, R = tex(NeatXPStyle.TEX.barL), tex(NeatXPStyle.TEX.barM), tex(NeatXPStyle.TEX.barR)
    local cap = math.floor(h * 0.5)
    local fr, fg, fb = NeatXPStyle.getFillColor(pct)
    local fw = math.floor(w * pct)

    if not (L and R) then
        el:drawRectStatic(x, y, w, h, 0.55, 0.09, 0.09, 0.10)
        if fw > 1 then el:drawRectStatic(x, y, fw, h, 0.95, fr, fg, fb) end
    else
        draw3(el, L, M, R, x, y, w, h, cap, 0.55, 0.09, 0.09, 0.10)
        if fw > 2 then
            el:setStencilRect(x, y, fw, h)
            draw3(el, L, M, R, x, y, w, h, cap, 0.95, fr, fg, fb)
            el:clearStencilRect()
        end
    end

    if label and label ~= "" and labelFont then
        local fh = getTextManager():getFontHeight(labelFont)
        local ty = y + math.floor((h - fh) / 2)
        local cx = x + math.floor(w / 2)
        local tr, tg, tb = NeatXPStyle.getColor("text")
        -- 1px dark backing keeps the readout legible over both the empty track
        -- and the bright end of the fill.
        el:drawTextCentre(label, cx + 1, ty + 1, 0, 0, 0, 0.75, labelFont)
        el:drawTextCentre(label, cx, ty, tr, tg, tb, 1, labelFont)
    end
end

-- ---- Text helpers ------------------------------------------------------------
-- getText returns the raw key when a translation is missing: never show that.
function NeatXPStyle.tr(key, fallback)
    if not getText then return fallback end
    local t = getText(key)
    if not t or t == key then return fallback end
    return t
end

-- Truncate text with ".." so it fits maxW (framework-style truncation).
function NeatXPStyle.fitText(text, maxW, font)
    text = tostring(text or "")
    local tm = getTextManager()
    if tm:MeasureStringX(font, text) <= maxW then return text end
    local out = text
    while #out > 1 and tm:MeasureStringX(font, out .. "..") > maxW do
        out = out:sub(1, #out - 1)
    end
    return out .. ".."
end

-- ---- Colour maths (shared with the picker) -----------------------------------
function NeatXPStyle.hsbToRgb(h, s, v)
    s = math.max(0, math.min(s or 0, 1))
    v = math.max(0, math.min(v or 0, 1))
    if s <= 0 then return v, v, v end
    h = ((h or 0) % 1) * 6
    local i = math.floor(h)
    local f = h - i
    local p = v * (1 - s)
    local q = v * (1 - s * f)
    local t = v * (1 - s * (1 - f))
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end

function NeatXPStyle.rgbToHsb(r, g, b)
    local mx = math.max(r, g, b)
    local mn = math.min(r, g, b)
    local d  = mx - mn
    local h  = 0
    if d > 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = ((b - r) / d) + 2
        else h = ((r - g) / d) + 4 end
        h = h / 6
    end
    local s = (mx > 0) and (d / mx) or 0
    return h % 1, s, mx
end

function NeatXPStyle.toHex(r, g, b)
    return string.format("#%02X%02X%02X",
        math.floor(math.max(0, math.min(r, 1)) * 255 + 0.5),
        math.floor(math.max(0, math.min(g, 1)) * 255 + 0.5),
        math.floor(math.max(0, math.min(b, 1)) * 255 + 0.5))
end

-- ---- Skill icon (bundled OSRS set, else drawn badge) ------------------------
local _iconCache = {}
function NeatXPStyle.getSkillIcon(skillType)
    if skillType == nil then return nil end
    local key = tostring(skillType):lower():gsub(" ", "_")
    if _iconCache[key] == nil then
        local t = getTexture("media/ui/NeatXP/icon_" .. key .. ".png")
        if not t then t = getTexture("media/ui/RUNE-EXP_icon_" .. key .. ".png") end
        _iconCache[key] = t or false
    end
    if _iconCache[key] == false then return nil end
    return _iconCache[key]
end

--[[ Le abilita' del gioco base, per nome del perk in minuscolo.

    Serve a rispondere a una domanda sola: **questa abilita' e' di vanilla?**
    Il motore non lo dice - per lui un perk aggiunto da una mod e' un perk come
    gli altri - e questo e' l'unico elenco che ce lo fa sapere.

    Non e' scritto a mano: sono i nomi dei nostri file icona, che coprono la
    dotazione di B42 uno per uno. Restano fuori i quattro che icone di abilita'
    non sono (`brush`, `traits*`, `unknown`).

    La domanda **non** e' piu' "abbiamo un'icona per questa?". Le due cose
    coincidono quasi sempre ma non sono la stessa: se una mod segue una
    convenzione di percorso che conosciamo, la sua abilita' ha un'icona vera e
    va mostrata: resta comunque roba di un'altra mod e sta nella sua sezione.

    Se un giorno il gioco aggiunge un'abilita', va aggiunta qui. Dimenticarsene
    non rompe niente: quell'abilita' finisce fra quelle delle altre mod.
]]
local VANILLA_SKILLS = {}
for _, name in ipairs({
    "aiming", "art", "axe", "blacksmith", "blunt", "butchering", "carving",
    "cleaning", "cooking", "dancing", "doctor", "driving", "efficiency",
    "electricity", "farming", "fishing", "fitness", "flintknapping",
    "glassmaking", "husbandry", "lightfoot", "lockpicking", "longblade",
    "maintenance", "masonry", "mechanics", "meditation", "metalwelding",
    "music", "nimble", "plantscavenging", "pottery", "reloading", "scavenging",
    "smallblade", "smallblunt", "sneak", "spear", "sprinting", "strength",
    "tailoring", "tracking", "trapping", "woodwork",
}) do VANILLA_SKILLS[name] = true end

--- Vera per un'abilita' aggiunta da un'altra mod.
function NeatXPStyle.isForeignSkill(skillType)
    if skillType == nil then return false end
    return not VANILLA_SKILLS[tostring(skillType):lower():gsub(" ", "_")]
end

--- Il pennello: il ripiego quando un'abilita' di un'altra mod non ha un'icona
--- che sappiamo trovare. Sta **solo** nella finestra di configurazione: nel
--- pannello un'abilita' senza icona non ne prende una finta.
function NeatXPStyle.brushIcon()
    return NeatXPStyle.tex("media/ui/NeatXP/icon_brush.png")
end

local function initials(name)
    if not name or name == "" then return "?" end
    name = tostring(name)
    local a, b = name:match("^(%a)%a*%s+(%a)")
    if a and b then return (a .. b):upper() end
    return name:sub(1, 2):upper()
end

function NeatXPStyle.drawIcon(el, x, y, size, skillType, skillName, alpha)
    alpha = alpha or 1.0
    local icon = NeatXPStyle.getSkillIcon(skillType)
    if icon then
        el:drawTextureScaled(icon, x, y, size, size, alpha, 1, 1, 1)
        return
    end
    -- Un'abilita' di un'altra mod di cui non troviamo l'icona non ne prende
    -- una finta: qui non si disegna niente. La pastiglia con le iniziali resta
    -- per le abilita' del gioco, dove "manca l'icona" vuol dire che manca a
    -- noi. Il pennello vive solo nella finestra di configurazione.
    if NeatXPStyle.isForeignSkill(skillType) then return end
    local font = NeatXPStyle.pickFont(size)
    el:drawTextCentre(initials(skillName), x + math.floor(size / 2),
        y + math.floor((size - getTextManager():getFontHeight(font)) / 2),
        NeatXPStyle.accent.r, NeatXPStyle.accent.g, NeatXPStyle.accent.b, alpha, font)
end
