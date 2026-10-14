-- Shared by the Conky configs and the Lua scripts: install/runtime paths,
-- settings.conf parsing, snapshot reading and the base window config.
local M = {}

M.dir = os.getenv('CONKY_PLAYER_DIR')
  or (os.getenv('HOME') .. '/.config/conky-player')
M.run = os.getenv('CONKY_PLAYER_RUN')
  or ((os.getenv('XDG_RUNTIME_DIR') or ('/dev/shm/' .. (os.getenv('USER') or 'user')))
      .. '/conky-player')

M.snapshot = M.run .. '/snapshot'
M.cover = M.run .. '/cover'
M.cava = M.run .. '/cava'
M.viz_off = M.run .. '/viz-off'

-- Vertical space reserved for the text panel above (or below) the visualizer.
M.PANEL_HEIGHT = 110
-- Horizontal offset of the text next to the 80 px cover art.
M.TEXT_X = 96

local defaults = {
  alignment = 'top_left', gap_x = '40', gap_y = '40', width = '380',
  color_text = '#E6DFD3', color_accent = '#E3BE8C', color_dim = '#9A9488',
  font = 'Inter', font_mono = 'JetBrains Mono', font_symbol = 'DejaVu Sans',
  font_cjk = 'Noto Sans CJK JP',
  visualizer = 'yes', viz_height = '50', viz_bars = '32', viz_fps = '60',
}

local function load_settings(path)
  local s = {}
  for k, v in pairs(defaults) do s[k] = v end
  local f = io.open(path)
  if f then
    for line in f:lines() do
      local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
      if k then s[k] = v end
    end
    f:close()
  end
  for _, k in ipairs { 'gap_x', 'gap_y', 'width', 'viz_height', 'viz_bars', 'viz_fps' } do
    s[k] = tonumber(s[k]) or tonumber(defaults[k])
  end
  return s
end

M.settings = load_settings(M.dir .. '/settings.conf')

-- '#RRGGBB' -> r, g, b in 0..1 (falls back to white on bad input).
function M.rgb(hex)
  local r, g, b = (hex or ''):match('^#?(%x%x)(%x%x)(%x%x)$')
  if not r then return 1, 1, 1 end
  return tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
end

-- Snapshot written by scripts/daemon.sh, one tab-separated line:
--   1 player  2 status  3 title  4 artist  5 position (m:ss)  6 length (m:ss)
--   7 position (us)  8 length (us)  9 art URL
function M.read_snapshot()
  local f = io.open(M.snapshot)
  if not f then return nil end
  local line = f:read('*l') or ''
  f:close()
  local fields = {}
  for v in (line .. '\t'):gmatch('([^\t]*)\t') do fields[#fields + 1] = v end
  return fields
end

-- Base Conky window config; `extra` overrides individual keys.
function M.window(extra)
  local s = M.settings
  local cfg = {
    alignment = s.alignment, gap_x = s.gap_x, gap_y = s.gap_y,
    own_window = true, own_window_type = 'dock',
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    own_window_argb_visual = true, own_window_argb_value = 0,
    own_window_class = 'conky', own_window_title = 'conky-player',
    double_buffer = true, update_interval = 1,
    use_xft = true, override_utf8_locale = true, font = s.font .. ':size=11',
    default_color = s.color_text, color1 = s.color_accent, color2 = s.color_dim,
    draw_shades = false, draw_outline = false, draw_borders = false,
    minimum_width = s.width, maximum_width = s.width,
    default_bar_height = 3, default_bar_width = 0,
  }
  for k, v in pairs(extra or {}) do cfg[k] = v end
  return cfg
end

-- The text panel and the visualizer are two windows stacked vertically:
-- panel on top for top_* alignments, visualizer at the edge for bottom_*.
local function at_bottom() return M.settings.alignment:match('^bottom') ~= nil end

function M.panel_gap_y()
  local s = M.settings
  return at_bottom() and s.gap_y + s.viz_height + 30 or s.gap_y
end

function M.viz_gap_y()
  local s = M.settings
  return at_bottom() and s.gap_y or s.gap_y + M.PANEL_HEIGHT
end

-- Replace @name@ placeholders in a conky.text template.
function M.template(text, vars)
  return (text:gsub('@([%w_]+)@', function(k) return tostring(vars[k]) end))
end

return M
