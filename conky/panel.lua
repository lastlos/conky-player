require 'cairo'
pcall(require, 'cairo_xlib')
require 'imlib2'
require 'cairo_imlib2_helper'

local dir = os.getenv('CONKY_PLAYER_DIR') or (os.getenv('HOME') .. '/.config/conky-player')
local C = dofile(dir .. '/conky/common.lua')
local S = C.settings

-- Layout in window coordinates. Baselines match the earlier Conky text
-- layout: player name 9 pt, title 12 pt bold, artist 11 pt, time 9 pt.
local X = C.TEXT_X
local MAXW = S.width - C.TEXT_X
local LINES = {
  { field = 11, text = 1, baseline = 39, size = 9,  bold = false, color = S.color_dim },
  { field = 12, text = 3, baseline = 62, size = 12, bold = true,  color = S.color_accent },
  { field = 13, text = 4, baseline = 81, size = 11, bold = false, color = S.color_text },
}
local TIME_BASELINE = 103

-- Marquee at the panel's 0.2 s update interval: 4 px per frame (20 px/s)
-- and a 2 s pause at either end.
local SPEED, PAUSE = 4, 10

local surfaces = {}   -- path -> cairo image surface (text PNGs, scaled cover)
local scroll = {}     -- line index -> { path, tick }

local function px(pt) return pt * 96 / 72 end

local function set_color(cr, hex, alpha)
  local r, g, b = C.rgb(hex)
  cairo_set_source_rgba(cr, r, g, b, alpha or 1)
end

-- Drop cached surfaces that the current snapshot no longer names.
local function prune(keep)
  for path, s in pairs(surfaces) do
    if not keep[path] then
      cairo_surface_destroy(s)
      surfaces[path] = nil
    end
  end
end

-- Cover art scaled once into an image surface. Conky's ${image} leaves alpha
-- at 0 on ARGB windows, so a compositor showed black parts of covers as
-- transparent; cairo_draw_image writes real alpha.
local function cover_surface(path)
  if surfaces[path] then return surfaces[path] end
  local img = imlib_load_image(path)
  if img == nil then return nil end
  imlib_context_set_image(img)
  local w, h = imlib_image_get_width(), imlib_image_get_height()
  imlib_free_image()
  if w == 0 or h == 0 then return nil end
  local s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, C.COVER_SIZE, C.COVER_SIZE)
  cairo_draw_image(path, s, 0, 0, C.COVER_SIZE / w, C.COVER_SIZE / h)
  surfaces[path] = s
  return s
end

local function png_surface(path)
  if surfaces[path] then return surfaces[path] end
  local s = cairo_image_surface_create_from_png(path)
  if cairo_surface_status(s) ~= CAIRO_STATUS_SUCCESS then
    cairo_surface_destroy(s)
    return nil
  end
  surfaces[path] = s
  return s
end

-- Horizontal offset into a text image of width w: still if it fits,
-- otherwise back and forth with a pause at each end. Right-to-left text
-- starts at its right end, where it begins.
local function marquee_offset(i, path, w, rtl)
  local range = w - MAXW
  if range <= 0 then return 0 end
  local st = scroll[i]
  if not st or st.path ~= path then
    st = { path = path, tick = 0 }
    scroll[i] = st
  end
  st.tick = st.tick + 1
  local run = math.ceil(range / SPEED)
  local k = st.tick % (2 * PAUSE + 2 * run)
  local off
  if     k < PAUSE           then off = 0
  elseif k < PAUSE + run     then off = (k - PAUSE) * SPEED
  elseif k < 2 * PAUSE + run then off = range
  else                            off = range - (k - 2 * PAUSE - run) * SPEED
  end
  off = math.max(0, math.min(range, off))
  return rtl and range - off or off
end

local function draw_text_image(cr, i, line, path)
  local s = png_surface(path)
  if not s then return false end
  local w, h = cairo_image_surface_get_width(s), cairo_image_surface_get_height(s)
  -- Anchored at the end: the hash before it may itself contain "-b<digit>".
  local rtl = path:match('%.rtl%.png$') ~= nil
  local base = tonumber(path:match(rtl and '%-b(%-?%d+)%.rtl%.png$' or '%-b(%-?%d+)%.png$')) or h
  local off = marquee_offset(i, path, w, rtl)
  local top = line.baseline - base
  cairo_save(cr)
  cairo_rectangle(cr, X, top, MAXW, h)
  cairo_clip(cr)
  cairo_set_source_surface(cr, s, X - off, top)
  cairo_paint(cr)
  cairo_restore(cr)
  return true
end

-- Fallback without python3-gi: cairo's toy text API, no shaping or font
-- fallback, clipped to the line width.
local function draw_plain(cr, line, text, font, size_pt, bold)
  cairo_save(cr)
  cairo_rectangle(cr, X, line.baseline - px(size_pt) * 1.5, MAXW, px(size_pt) * 2)
  cairo_clip(cr)
  cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL,
    bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(cr, px(size_pt))
  set_color(cr, line.color)
  cairo_move_to(cr, X, line.baseline)
  cairo_show_text(cr, text)
  cairo_restore(cr)
end

-- Font faces are created once: selecting them by name on every frame costs
-- a fontconfig lookup each time.
local faces = {}
local function face(family)
  if not faces[family] then
    faces[family] = cairo_toy_font_face_create(family, CAIRO_FONT_SLANT_NORMAL,
      CAIRO_FONT_WEIGHT_NORMAL)
  end
  return faces[family]
end

local icon_advance = {}
local function draw_time(cr, fields)
  set_color(cr, S.color_dim)
  cairo_set_font_face(cr, face(S.font_symbol))
  cairo_set_font_size(cr, px(8))
  local icon = fields[2] == 'Playing' and '▶' or '▮▮'
  if not icon_advance[icon] then
    local ext = cairo_text_extents_t:create()
    tolua.takeownership(ext)
    cairo_text_extents(cr, icon, ext)
    icon_advance[icon] = ext.x_advance
  end
  -- Raised to sit where Conky's Xft text put it.
  cairo_move_to(cr, X, TIME_BASELINE - 2)
  cairo_show_text(cr, icon)
  cairo_set_font_face(cr, face(S.font_mono))
  cairo_set_font_size(cr, px(9))
  cairo_move_to(cr, X + icon_advance[icon], TIME_BASELINE)
  cairo_show_text(cr, ' ' .. (fields[5] or '') .. ' / ' .. (fields[6] or ''))
end

function conky_draw_panel()
  if conky_window == nil then return end
  local fields = C.read_snapshot()
  if not fields then
    prune({})
    return
  end
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
    conky_window.visual, conky_window.width, conky_window.height)
  local cr = cairo_create(cs)
  local keep = {}

  local cover = C.run_file(fields, 10)
  local s = cover and cover_surface(cover)
  if s then
    keep[cover] = true
    cairo_set_source_surface(cr, s, conky_window.text_start_x, conky_window.text_start_y)
    cairo_paint(cr)
  end

  for i, line in ipairs(LINES) do
    local path = C.run_file(fields, line.field)
    if path and draw_text_image(cr, i, line, path) then
      keep[path] = true
    elseif (fields[line.text] or '') ~= '' then
      draw_plain(cr, line, fields[line.text], S.font, line.size, line.bold)
    end
  end

  draw_time(cr, fields)
  prune(keep)
  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end
