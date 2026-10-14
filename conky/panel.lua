require 'cairo'

local dir = os.getenv('CONKY_PLAYER_DIR') or (os.getenv('HOME') .. '/.config/conky-player')
local C = dofile(dir .. '/conky/common.lua')

-- Scratch surface used only to measure text.
local mcs = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 10, 10)
local mcr = cairo_create(mcs)
local mq = {}
local BASE_FONT, CJK_FONT = C.settings.font, C.settings.font_cjk

local function field(n)
  local fields = C.read_snapshot()
  return fields and fields[n] or ''
end

local function is_cjk(c)
  return (c >= 0x3000 and c <= 0x9FFF) or (c >= 0xAC00 and c <= 0xD7AF)
      or (c >= 0xF900 and c <= 0xFAFF) or (c >= 0xFF00 and c <= 0xFFEF)
end

local function chars(s)
  local t, cjk = {}, {}
  local ok = pcall(function()
    for _, c in utf8.codes(s) do t[#t + 1] = utf8.char(c); cjk[#cjk + 1] = is_cjk(c) end
  end)
  if not ok then
    t, cjk = {}, {}
    for c in s:gmatch('.') do t[#t + 1] = c; cjk[#cjk + 1] = false end
  end
  return t, cjk
end

local function width(str, face, bold, px)
  cairo_select_font_face(mcr, face, CAIRO_FONT_SLANT_NORMAL,
    bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(mcr, px)
  local ext = cairo_text_extents_t:create()
  tolua.takeownership(ext)
  cairo_text_extents(mcr, str, ext)
  return ext.x_advance
end

local function metrics(face, bold, px)
  cairo_select_font_face(mcr, face, CAIRO_FONT_SLANT_NORMAL,
    bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
  cairo_set_font_size(mcr, px)
  local fe = cairo_font_extents_t:create()
  tolua.takeownership(fe)
  cairo_font_extents(mcr, fe)
  return fe.ascent, fe.descent
end

local function render(st, i, j, bold, size)
  local out, k, any = {}, i, false
  while k <= j do
    local c = st.cjk[k]
    if c then any = true end
    local run = {}
    while k <= j and st.cjk[k] == c do run[#run + 1] = st.ch[k]; k = k + 1 end
    local face = c and CJK_FONT or BASE_FONT
    local txt = table.concat(run):gsub('%$', '$$'):gsub('#', '\\#')
    out[#out + 1] = '${font ' .. face .. (bold and ':bold' or '') .. ':size=' .. size .. '}'
    out[#out + 1] = txt
  end
  local res = table.concat(out)
  if any then
    local px = size * 96 / 72
    local a1, d1 = metrics(BASE_FONT, bold, px)
    local a2, d2 = metrics(CJK_FONT, bold, px)
    local da = math.max(0, math.floor(a2 - a1 + 0.5))
    local dd = math.max(0, math.floor(d2 - d1 + 0.5))
    res = '${voffset -' .. da .. '}' .. res .. '${voffset -' .. dd .. '}'
  end
  return res
end

function conky_pmarq(n, bold, pt, maxw)
  n, bold, maxw = tonumber(n), bold == '1', tonumber(maxw)
  local size = tonumber(pt)
  local px = size * 96 / 72
  local s = field(n)
  local st = mq[n]
  if not st or st.s ~= s then
    st = { s = s, tick = 0 }
    st.ch, st.cjk = chars(s)
    local N = #st.ch
    st.adv = {}
    for k = 1, N do
      st.adv[k] = width(st.ch[k], st.cjk[k] and CJK_FONT or BASE_FONT, bold, px)
    end
    local function w(i, j) local t = 0 for k = i, j do t = t + st.adv[k] end return t end
    if N == 0 or w(1, N) <= maxw then
      st.fixed = true
    else
      local R = N
      while R > 1 and w(R - 1, N) <= maxw do R = R - 1 end
      st.R, st.vis = R, {}
      for i = 1, R do
        local j = i
        while j < N and w(i, j + 1) <= maxw do j = j + 1 end
        st.vis[i] = j
      end
    end
    mq[n] = st
  end

  if #st.ch == 0 then return '' end
  if st.fixed then return render(st, 1, #st.ch, bold, size) end

  st.tick = st.tick + 1
  local P, R = 4, st.R - 1
  local k = st.tick % (2 * R + 2 * P)
  local pos
  if     k < P         then pos = 0
  elseif k < P + R     then pos = k - P
  elseif k < 2 * P + R then pos = R
  else                      pos = R - (k - 2 * P - R)
  end
  return render(st, pos + 1, st.vis[pos + 1], bold, size)
end
