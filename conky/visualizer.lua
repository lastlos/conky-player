require 'cairo'
pcall(require, 'cairo_xlib')

local R, G, B = 0.89, 0.745, 0.549   -- #E3BE8C
local VH = 50
local active, pct, last = false, 0, -1

local function update()
  local t = os.time()
  if t == last then return end
  last = t
  active, pct = false, 0
  local off = io.open("/dev/shm/conky-viz-off")
  if off then off:close(); return end
  local f = io.open("/dev/shm/conky-player.txt")
  if not f then return end
  local line = f:read("*l") or ""; f:close()
  local fields = {}
  for v in (line .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = v end
  local pos, len = tonumber(fields[7]), tonumber(fields[8])
  active = true
  pct = (pos and len and len > 0) and pos / len or 0
end

function conky_draw()
  if conky_window == nil then return end
  update()
  if not active then return end
  local W = conky_window.width
  local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
    conky_window.visual, W, conky_window.height)
  local cr = cairo_create(cs)

  local f = io.open('/dev/shm/cava.txt')
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
