require 'cairo'
pcall(require, 'cairo_xlib')

local dir = os.getenv('CONKY_PLAYER_DIR') or (os.getenv('HOME') .. '/.config/conky-player')
local C = dofile(dir .. '/conky/common.lua')

local R, G, B = C.rgb(C.settings.color_accent)
local VH = C.settings.viz_height
local active, pct, last = false, 0, -1

-- Re-read the snapshot at most once a second; the daemon does not write faster.
local function update()
  local t = os.time()
  if t == last then return end
  last = t
  active, pct = false, 0
  local off = io.open(C.viz_off)
  if off then off:close(); return end
  local fields = C.read_snapshot()
  if not fields then return end
  local pos, len = tonumber(fields[7]), tonumber(fields[8])
  active = true
  pct = (pos and len and len > 0) and math.min(1, pos / len) or 0
end

function conky_draw()
  if conky_window == nil then return end
  update()
  if not active then return end
  local W = conky_window.width
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
    conky_window.visual, W, conky_window.height)
  local cr = cairo_create(cs)

  local f = io.open(C.cava)
  if f then
    local line = f:read('*l'); f:close()
    local vals = {}
    for v in (line or ''):gmatch('%d+') do vals[#vals + 1] = tonumber(v) end
    if #vals > 0 then
      local bw = W / #vals
      cairo_set_source_rgba(cr, R, G, B, 0.8)
      for i, v in ipairs(vals) do
        local bh = math.max(1, v / 100 * VH)
        cairo_rectangle(cr, (i - 1) * bw + 1, VH - bh, bw - 2, bh)
      end
      cairo_fill(cr)
    end
  end

  cairo_set_source_rgba(cr, R, G, B, 0.25)
  cairo_rectangle(cr, 0, VH + 3, W, 2)
  cairo_fill(cr)
  cairo_set_source_rgba(cr, R, G, B, 0.95)
  cairo_rectangle(cr, 0, VH + 3, W * pct, 2)
  cairo_fill(cr)

  cairo_destroy(cr)
  cairo_surface_destroy(cs)
end
