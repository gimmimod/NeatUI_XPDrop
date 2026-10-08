--[[ ============================================================================
    NeatXPColorPicker - minimal HSB colour picker in the NeatUI idiom.

    Rebuilt from scratch rather than derived from ISColorPicker / ISColorPickerHSB:
    the vanilla pickers put their controls in child ISUIElements, and this panel
    runs with setCapture(true) (it is opened over the Mod Options screen), where
    child mouse routing is unreliable. Every control here is drawn and hit-tested
    by the panel itself, so capture behaves.

    Anatomy is the standard Neat window: rounded MainTitle_BG header with a red
    square close button, MainPanelBG_FlatTop body, InnerPanel_BG wells, 3-slice
    Button_FULL footer buttons, orange accent.

    Contract expected by NeatXPSettings (mirrors ISColorPicker so the Mod Options
    plumbing does not have to care which picker is open):
        picker.pickedTarget / picker.pickedFunc(target, {r,g,b}, mouseUp)
        picker:setInitialColor(ColorInfo)
============================================================================ ]]--

require "ISUI/ISPanel"
require "NeatXPDrops/NeatXPStyle"

NeatXPColorPicker = ISPanel:derive("NeatXPColorPicker")

-- Geometry is deliberately identical to NeatUI Hairstyler's IHM_NeatColorPicker:
-- the two mods sit in the same Options screen, and a colour picker that changes
-- size and proportion depending on which row you clicked is just noise.
local SQUARE   = 176     -- saturation x brightness square
local RAIL_W   = 16      -- hue rail
local GAP      = 8
local PAD      = 10
local SIDE_W   = 104     -- preview / hex column
local SWATCH   = 18
local SW_GAP   = 4

-- A compact, deliberately unsaturated set: neutrals, the Neat accent, and the
-- hues that read well on a dark panel.
local PRESETS = {
    { 1.00, 1.00, 1.00 }, { 0.72, 0.72, 0.72 }, { 0.45, 0.45, 0.45 },
    { 0.95, 0.50, 0.10 }, { 0.95, 0.78, 0.20 }, { 0.40, 0.80, 0.42 },
    { 0.30, 0.72, 0.68 }, { 0.35, 0.60, 0.95 }, { 0.62, 0.45, 0.90 },
    { 0.90, 0.30, 0.35 },
}

-- Exposed so a caller can build its own row on top of the shared set instead of
-- inventing a second palette (NeatXPSettings prepends the option's default).
NeatXPColorPicker.PRESETS = PRESETS

local function inRect(mx, my, r)
    return r and mx >= r.x and mx <= r.x + r.w and my >= r.y and my <= r.y + r.h
end

-- =============================================================================
-- Construction
-- =============================================================================

function NeatXPColorPicker:new(x, y, title)
    local titleFont, titleH = NeatXPStyle.pickFont(18)
    local bodyFont,  bodyH  = NeatXPStyle.pickFont(15)

    local headerH = titleH + 14
    local btnH    = bodyH + 10
    local w = PAD + SQUARE + GAP + RAIL_W + GAP + SIDE_W + PAD

    local o = ISPanel:new(x, y, w, 10)   -- height set once the palette is known
    setmetatable(o, self)
    self.__index = self

    o.background = false
    o.title      = title or NeatXPStyle.tr("IGUI_NeatXP_ColorTitle", "Colour")
    o.titleFont  = titleFont
    o.bodyFont   = bodyFont
    o.headerH    = headerH
    o.btnH       = btnH

    o.h, o.s, o.b = 0, 0, 1
    o.initial     = { r = 1, g = 1, b = 1 }
    o.pickedArgs  = {}

    -- Hit rects, all fixed for the life of the panel.
    o.rSquare = { x = PAD,                        y = headerH + PAD, w = SQUARE, h = SQUARE }
    o.rRail   = { x = PAD + SQUARE + GAP,         y = headerH + PAD, w = RAIL_W, h = SQUARE }
    local sideX = PAD + SQUARE + GAP + RAIL_W + GAP
    o.rPreview = { x = sideX, y = headerH + PAD, w = SIDE_W, h = 44 }
    o.rHex     = { x = sideX, y = headerH + PAD + 50, w = SIDE_W, h = bodyH + 4 }

    o.paletteCols = math.max(1, math.floor((w - PAD * 2 + SW_GAP) / (SWATCH + SW_GAP)))
    o.paletteRows = 0
    o.palette     = {}
    o.swatches    = {}

    o.labelConfirm = NeatXPStyle.tr("IGUI_NeatXP_Confirm", "Confirm")
    o.labelCancel  = NeatXPStyle.tr("IGUI_NeatXP_Cancel", "Cancel")
    o.labelDefault = NeatXPStyle.tr("IGUI_NeatXP_Default", "Default")

    o.closeSize = titleH
    o.rClose = { x = w - PAD - o.closeSize, y = math.floor((headerH - o.closeSize) / 2),
                 w = o.closeSize, h = o.closeSize }

    o:setPalette(nil)
    return o
end

function NeatXPColorPicker:initialise() ISPanel.initialise(self) end

--[[ Lay the swatch grid out and size the panel around it.

    nil means "the built-in presets". A caller can pass its own list instead, in
    which case the grid wraps onto as many rows as it needs and the footer moves
    down with it - the same contract IHM_NeatColorPicker exposes, so the two
    pickers stay interchangeable.
]]
function NeatXPColorPicker:setPalette(colors)
    self.palette = {}
    for _, c in ipairs(colors or PRESETS) do
        local r = c.r or c[1]
        local g = c.g or c[2]
        local b = c.b or c[3]
        if r and g and b then table.insert(self.palette, { r = r, g = g, b = b }) end
    end

    local cols = self.paletteCols
    self.paletteRows = math.ceil(#self.palette / cols)

    local pY = self.headerH + PAD + SQUARE + GAP
    self.swatches = {}
    for i, c in ipairs(self.palette) do
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        table.insert(self.swatches, {
            x = PAD + col * (SWATCH + SW_GAP),
            y = pY + row * (SWATCH + SW_GAP),
            w = SWATCH, h = SWATCH,
            r = c.r, g = c.g, b = c.b,
        })
    end

    local paletteH = 0
    if self.paletteRows > 0 then
        paletteH = self.paletteRows * (SWATCH + SW_GAP) - SW_GAP + GAP
    end

    local h = self.headerH + PAD + SQUARE + GAP + paletteH + self.btnH + PAD
    self:setHeight(h)

    local tm = getTextManager()
    local bw = math.max(70, 24 + math.max(
        tm:MeasureStringX(self.bodyFont, self.labelConfirm),
        tm:MeasureStringX(self.bodyFont, self.labelCancel),
        tm:MeasureStringX(self.bodyFont, self.labelDefault)))
    local by = h - PAD - self.btnH
    self.btnConfirm = { x = self.width - PAD - bw,         y = by, w = bw, h = self.btnH, label = self.labelConfirm }
    self.btnCancel  = { x = self.width - PAD - bw * 2 - 8, y = by, w = bw, h = self.btnH, label = self.labelCancel }
    self.btnReset   = { x = PAD,                           y = by, w = bw, h = self.btnH, label = self.labelDefault }
end

-- =============================================================================
-- Colour state
-- =============================================================================

function NeatXPColorPicker:getRGB()
    return NeatXPStyle.hsbToRgb(self.h, self.s, self.b)
end

function NeatXPColorPicker:setRGB(r, g, b)
    self.h, self.s, self.b = NeatXPStyle.rgbToHsb(r, g, b)
end

-- ColorInfo in, matching ISColorPicker:setInitialColor.
function NeatXPColorPicker:setInitialColor(colorInfo)
    local r, g, b = 1, 1, 1
    if colorInfo then
        local ok = pcall(function()
            r, g, b = colorInfo:getR(), colorInfo:getG(), colorInfo:getB()
        end)
        if not ok then r, g, b = 1, 1, 1 end
    end
    self.initial = { r = r, g = g, b = b }
    self:setRGB(r, g, b)
end

function NeatXPColorPicker:setDefaultColor(r, g, b)
    self.defaultColor = { r = r, g = g, b = b }
end

-- Live feedback, same shape as ISColorPicker's pickedFunc call.
function NeatXPColorPicker:emit(mouseUp)
    if not self.pickedFunc then return end
    local r, g, b = self:getRGB()
    self.pickedFunc(self.pickedTarget, { r = r, g = g, b = b }, mouseUp,
        self.pickedArgs[1], self.pickedArgs[2], self.pickedArgs[3], self.pickedArgs[4])
end

-- =============================================================================
-- Render
-- =============================================================================

function NeatXPColorPicker:prerender()
    local w, h = self.width, self.height
    local mx, my = self:getMouseX(), self:getMouseY()
    local over = self:isMouseOver()

    NeatXPStyle.drawWindow(self, 0, 0, w, h, self.headerH, 1.0, 1.0)
    self:drawText(self.title, PAD,
        math.floor((self.headerH - NeatXPStyle.fontHeight(self.titleFont)) / 2),
        1, 1, 1, 1, self.titleFont)

    -- close X
    local closeHover = over and inRect(mx, my, self.rClose)
    local cr, cg, cb = 0.8, 0.2, 0.2
    if closeHover then cr, cg, cb = 0.96, 0.24, 0.24 end
    local bgT = NeatXPStyle.tex("media/ui/NeatUI/Button/Background.png")
    if bgT then
        self:drawTextureScaled(bgT, self.rClose.x, self.rClose.y, self.rClose.w, self.rClose.h, 0.8, cr, cg, cb)
    else
        self:drawRect(self.rClose.x, self.rClose.y, self.rClose.w, self.rClose.h, 0.8, cr, cg, cb)
    end
    local xIcon = NeatXPStyle.tex("media/ui/NeatUI/ICON/Icon_False.png")
    if xIcon then
        local isz = math.floor(self.rClose.w * 0.8)
        local off = math.floor((self.rClose.w - isz) / 2)
        self:drawTextureScaled(xIcon, self.rClose.x + off, self.rClose.y + off, isz, isz, 1, 1, 1, 1)
    end

    self:drawSquare()
    self:drawRail()
    self:drawSide()

    -- preset swatches
    for _, sw in ipairs(self.swatches) do
        self:drawRect(sw.x, sw.y, sw.w, sw.h, 1, sw.r, sw.g, sw.b)
        local hovered = over and inRect(mx, my, sw)
        if hovered then
            self:drawRectBorder(sw.x - 1, sw.y - 1, sw.w + 2, sw.h + 2, 1, 1, 1, 1)
        else
            self:drawRectBorder(sw.x, sw.y, sw.w, sw.h, 0.55, 0, 0, 0)
        end
    end

    -- footer buttons. Default only appears when a caller supplied one, so the
    -- panel never shows a button that would do nothing.
    local fh = NeatXPStyle.fontHeight(self.bodyFont)
    local footer = { self.btnCancel, self.btnConfirm }
    if self.defaultColor then table.insert(footer, 1, self.btnReset) end
    for _, btn in ipairs(footer) do
        local hovered = over and inRect(mx, my, btn)
        local state = hovered and "hover" or nil
        if btn == self.btnConfirm then state = hovered and "activeHover" or "active" end
        NeatXPStyle.drawButton(self, btn.x, btn.y, btn.w, btn.h, state)
        self:drawTextCentre(btn.label, btn.x + math.floor(btn.w / 2),
            btn.y + math.floor((btn.h - fh) / 2), 1, 1, 1, 1, self.bodyFont)
    end
end

-- Saturation (x) by brightness (y) for the current hue. Uses the vanilla
-- ColorPicker gradients when present; otherwise a computed cell grid, so the
-- picker still works if a build ever drops those textures.
function NeatXPColorPicker:drawSquare()
    local r = self.rSquare
    local hueR, hueG, hueB = NeatXPStyle.hsbToRgb(self.h, 1, 1)
    local hueTex = NeatXPStyle.tex("media/ui/ColorPicker/ColorPicker_Hue.png")
    local satTex = NeatXPStyle.tex("media/ui/ColorPicker/ColorPicker_Sat.png")

    if hueTex and satTex then
        self:drawTextureScaled(hueTex, r.x, r.y, r.w, r.h, 1, hueR, hueG, hueB)
        self:drawTextureScaled(satTex, r.x, r.y, r.w, r.h, 1, 1, 1, 1)
    else
        local cells = 24
        local cw = r.w / cells
        local ch = r.h / cells
        for ix = 0, cells - 1 do
            for iy = 0, cells - 1 do
                local cr, cg, cb = NeatXPStyle.hsbToRgb(self.h, ix / (cells - 1), 1 - iy / (cells - 1))
                self:drawRect(r.x + math.floor(ix * cw), r.y + math.floor(iy * ch),
                    math.ceil(cw), math.ceil(ch), 1, cr, cg, cb)
            end
        end
    end
    self:drawRectBorder(r.x, r.y, r.w, r.h, 0.8, 0.45, 0.45, 0.45)

    -- cursor: white ring, black ring, current colour core
    local cx = r.x + math.floor(r.w * self.s)
    local cy = r.y + math.floor(r.h * (1 - self.b))
    local cr, cg, cb = self:getRGB()
    self:drawRectBorder(cx - 6, cy - 6, 13, 13, 1, 1, 1, 1)
    self:drawRectBorder(cx - 5, cy - 5, 11, 11, 1, 0, 0, 0)
    self:drawRect(cx - 4, cy - 4, 9, 9, 1, cr, cg, cb)
end

-- Hue rail: no bundled vertical hue strip exists, so it is drawn as thin bands.
function NeatXPColorPicker:drawRail()
    local r = self.rRail
    local bands = r.h
    for i = 0, bands - 1 do
        local hr, hg, hb = NeatXPStyle.hsbToRgb(i / bands, 1, 1)
        self:drawRect(r.x, r.y + i, r.w, 1, 1, hr, hg, hb)
    end
    self:drawRectBorder(r.x, r.y, r.w, r.h, 0.8, 0.45, 0.45, 0.45)

    local cy = r.y + math.floor(r.h * self.h)
    self:drawRect(r.x - 2, cy - 1, r.w + 4, 3, 1, 0, 0, 0)
    self:drawRect(r.x - 1, cy - 1, r.w + 2, 1, 1, 1, 1, 1)
    self:drawRect(r.x - 1, cy + 1, r.w + 2, 1, 1, 1, 1, 1)
end

function NeatXPColorPicker:drawSide()
    local p = self.rPreview
    NeatXPStyle.drawNP(self, NeatXPStyle.TEX.innerPanel, p.x - 3, p.y - 3, p.w + 6, p.h + 6, 0.16, 0.93)

    local half = math.floor(p.w / 2)
    local ini = self.initial
    local cr, cg, cb = self:getRGB()
    self:drawRect(p.x, p.y, half, p.h, 1, ini.r, ini.g, ini.b)
    self:drawRect(p.x + half, p.y, p.w - half, p.h, 1, cr, cg, cb)
    self:drawRectBorder(p.x, p.y, p.w, p.h, 0.8, 0.45, 0.45, 0.45)
    self:drawRect(p.x + half, p.y, 1, p.h, 0.8, 0.1, 0.1, 0.1)

    local acc = NeatXPStyle.accent
    self:drawTextCentre(NeatXPStyle.toHex(cr, cg, cb),
        self.rHex.x + math.floor(self.rHex.w / 2), self.rHex.y,
        acc.r, acc.g, acc.b, 1, self.bodyFont)
end

-- =============================================================================
-- Input
-- =============================================================================

function NeatXPColorPicker:onMouseDown(x, y)
    -- setCapture(true) routes every click here, including ones outside the panel.
    if self:isCapture() and not self:isMouseOver() then
        return self:onMouseDownOutside(x, y)
    end

    if inRect(x, y, self.rClose) then self:cancel(); return true end
    if inRect(x, y, self.btnCancel) then self:cancel(); return true end
    if inRect(x, y, self.btnConfirm) then self:confirm(); return true end
    if self.defaultColor and inRect(x, y, self.btnReset) then
        local d = self.defaultColor
        self:setRGB(d.r, d.g, d.b)
        self:emit(true)
        return true
    end

    for _, sw in ipairs(self.swatches) do
        if inRect(x, y, sw) then
            self:setRGB(sw.r, sw.g, sw.b)
            self:emit(true)
            return true
        end
    end

    if inRect(x, y, self.rSquare) then
        self.dragSquare = true
        self:applySquare(x, y)
        return true
    end
    if inRect(x, y, self.rRail) then
        self.dragRail = true
        self:applyRail(y)
        return true
    end

    -- Header drag: the panel is anchored under its swatch button, which on a
    -- short options list can land it over the row you are trying to compare
    -- against. Move it instead of closing it.
    if y >= 0 and y < self.headerH then
        self.moving = true
    end
    return true
end

function NeatXPColorPicker:onMouseDownOutside(x, y)
    -- Clicking away keeps whatever the live preview already applied, mirroring
    -- how the vanilla mod-options picker behaves.
    self:confirm()
    return true
end

function NeatXPColorPicker:applySquare(x, y)
    local r = self.rSquare
    local s = (x - r.x) / r.w
    local b = 1 - (y - r.y) / r.h
    self.s = math.max(0, math.min(s, 1))
    self.b = math.max(0, math.min(b, 1))
    self:emit(false)
end

function NeatXPColorPicker:applyRail(y)
    local r = self.rRail
    self.h = math.max(0, math.min((y - r.y) / r.h, 0.9999))
    self:emit(false)
end

function NeatXPColorPicker:onMouseMove(dx, dy)
    if self.dragSquare then self:applySquare(self:getMouseX(), self:getMouseY())
    elseif self.dragRail then self:applyRail(self:getMouseY())
    elseif self.moving then
        self:setX(self:getX() + dx)
        self:setY(self:getY() + dy)
    end
end

function NeatXPColorPicker:onMouseMoveOutside(dx, dy)
    self:onMouseMove(dx, dy)
end

function NeatXPColorPicker:onMouseUp(x, y)
    if self.dragSquare or self.dragRail then self:emit(true) end
    self.dragSquare, self.dragRail, self.moving = false, false, false
    return true
end

function NeatXPColorPicker:onMouseUpOutside(x, y) return self:onMouseUp(x, y) end

function NeatXPColorPicker:isKeyConsumed(key) return key == Keyboard.KEY_ESCAPE end

function NeatXPColorPicker:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE then self:cancel() end
end

-- =============================================================================
-- Close
-- =============================================================================

function NeatXPColorPicker:confirm()
    self:emit(true)
    if self.onConfirm then self.onConfirm(self) end
    self:removeSelf()
end

function NeatXPColorPicker:cancel()
    self:setRGB(self.initial.r, self.initial.g, self.initial.b)
    self:emit(true)
    if self.onCancel then self.onCancel(self) end
    self:removeSelf()
end

function NeatXPColorPicker:removeSelf()
    self:setCapture(false)
    self:setVisible(false)
    if self.parent then
        self.parent:removeChild(self)
    else
        self:removeFromUIManager()
    end
end
