-- opxy_viz.lua
-- Visual-first app + bass sequence
-- enc1: browse animations (continuous) / changes bass sequence
-- enc2: morph
-- enc3: speed
-- K2: generate new sequence for current animation
-- K3: play/stop
--
-- Bass: drunk-walk octave sequence, varying octaves only
-- Uses PolyPerc engine

engine.name = "PolyPerc"
local musicutil = require "musicutil"

-- ======================
-- Global state
-- ======================
local fps = 30
local t = 0
local last_time = 0
local sel = 1.0      -- continuous selection across animations
local morph = 0.5    -- 0..1
local speed = 1.0    -- 0.2..2.0
local mix_accum = 0.0
local anims = {}

-- sequencing
local playing = true
local seqs = {}           -- seqs[anim_index] = {octaves...}
local current_anim = 1
local step_i = 1

-- visual-musical link: note pulse envelope (0..1, decays each frame)
local note_pulse = 0.0
local note_pulse_decay = 0.88  -- per-frame multiplier

-- audio-reactive state
local audio_reactive = false
local amp_level = 0.0
local amp_smooth = 0.0

-- MIDI burst state
local midi_burst_active = false
local midi_burst_intensity = 0.0

-- ======================
-- Utilities
-- ======================
local function clamp(x, a, b)
  if x < a then return a end
  if x > b then return b end
  return x
end

local function lerp(a, b, u) return a + (b - a) * u end

local function ease_punch(u)
  -- fast in, tiny overshoot
  if u < 0.7 then
    local x = u / 0.7
    return x * x * (3 - 2 * x)
  else
    local x = (u - 0.7) / 0.3
    return 1.0 + 0.10 * math.sin((1 - x) * math.pi) * (1 - x)
  end
end

local function tri(x)
  local f = x - math.floor(x)
  if f < 0.5 then return f * 2 else return (1 - f) * 2 end
end

local function choose_temporal_mix(blend)
  -- error diffusion over time: returns true when frame B should show
  mix_accum = mix_accum + blend
  if mix_accum >= 1.0 then
    mix_accum = mix_accum - 1.0
    return true
  else
    return false
  end
end

-- ======================
-- Grain (cheap texture)
-- ======================
local function draw_grain(time, m)
  local grain_n = math.floor(lerp(14, 70, m) + 0.5)
  screen.level(1)
  for i = 1, grain_n do
    local gx = (math.sin(time * (7.1 + i * 0.17)) * 0.5 + 0.5) * 127
    local gy = (math.cos(time * (6.3 + i * 0.21)) * 0.5 + 0.5) * 63
    screen.pixel(gx, gy)
  end
  screen.fill()
end

-- ======================
-- Audio reactive polling
-- ======================
local function poll_audio_level()
  if audio_reactive then
    poll.set("amp_in_l")
  end
end

-- ======================
-- Animations (1..11 contiguous)
-- ======================

-- 1) RADIAL BURST
anims[1] = {
  name = "RADIAL",
  draw = function(time, m)
    local cx, cy = 64, 32
    local spokes = math.floor(lerp(6, 30, m) + 0.5)
    local maxr = lerp(18, 42, m)
    local phase = (time * (0.7 + 1.6 * speed)) % 1.0
    local punch = ease_punch(phase)
    local j = lerp(0.0, 1.7, m)
    local jx = (math.sin(time * 19.7) + math.sin(time * 7.3)) * 0.5 * j
    local jy = (math.cos(time * 17.1) + math.cos(time * 6.1)) * 0.5 * j
    -- note pulse: expand rings on trigger
    local pulse_r = note_pulse * lerp(4, 12, m)
    -- audio-reactive: boost maxr based on amplitude
    local audio_boost = amp_level * lerp(6, 18, m)
    for k = 1, 5 do
      local u = (k - 1) / 4
      local r = (maxr + audio_boost) * punch * (0.55 + 0.55 * u) + pulse_r
      local lvl = math.floor(lerp(15, 2, u) + 0.5)
      screen.level(lvl)
      screen.circle(cx + jx, cy + jy, r)
      screen.stroke()
    end
    local spoke_len = lerp(12, 34, m) * punch
    for i = 1, spokes do
      local a = (i / spokes) * (math.pi * 2)
      local wob = lerp(0.0, 0.28, m) * math.sin(time * 11.0 + i * 0.7)
      local aa = a + wob
      local x1 = cx + jx + math.cos(aa) * (2 + 6 * (1 - punch))
      local y1 = cy + jy + math.sin(aa) * (2 + 6 * (1 - punch))
      local x2 = cx + jx + math.cos(aa) * (2 + spoke_len)
      local y2 = cy + jy + math.sin(aa) * (2 + spoke_len)
      local lvl = 6 + (i % 3) * 3
      screen.level(clamp(lvl, 2, 15))
      screen.move(x1, y1)
      screen.line(x2, y2)
      screen.stroke()
    end
    screen.level(15)
    screen.circle(cx + jx, cy + jy, 2 + 5 * punch + pulse_r * 0.5)
    screen.fill()
  end
}

-- 2) SCANLINE
anims[2] = {
  name = "SCAN",
  draw = function(time, m)
    local w, h = 128, 64
    local rate = (0.35 + 1.9 * speed)
    local p = (time * rate) % 1.0
    local y = 2 + p * (h - 4)
    local thickness = lerp(3, 16, m) + note_pulse * 6 + amp_level * 4
    local wobble = lerp(0.3, 3.2, m)
    local flutter = math.sin(time * 9.0) * wobble + math.sin(time * 21.0) * wobble * 0.35
    for k = 1, 5 do
      local u = (k - 1) / 4
      local lvl = math.floor(lerp(15, 2, u) + 0.5)
      local th = thickness * (0.35 + 0.85 * u)
      screen.level(lvl)
      screen.rect(0, (y + flutter) - th * 0.5, w, th)
      screen.fill()
    end
    local lines = math.floor(lerp(6, 26, m) + 0.5)
    for i = 1, lines do
      local yy = (i / lines) * h
      local amp = lerp(0.2, 2.4, m)
      local xoff = (math.sin(time * 13.0 + i * 0.8) + math.sin(time * 5.0 + i * 2.1)) * 0.5 * amp
      local lvl = (i % 2 == 0) and 4 or 2
      screen.level(lvl)
      screen.move(0 + xoff, yy)
      screen.line(127 + xoff, yy)
      screen.stroke()
    end
    local ripple = lerp(0.0, 1.0, m)
    if ripple > 0.02 then
      local cx, cy = 64, 32
      local rr = (p * 42)
      screen.level(math.floor(lerp(3, 10, ripple) + 0.5))
      screen.circle(cx, cy, rr)
      screen.stroke()
      screen.level(2)
      screen.circle(cx, cy, rr * 0.7)
      screen.stroke()
    end
  end
}

-- 3) TARGET
anims[3] = {
  name = "TARGET",
  draw = function(time, m)
    local cx, cy = 64, 32
    local rings = math.floor(lerp(3, 9, m) + 0.5)
    local rotq = lerp(0.0, 1.0, m)
    local ang = time * (0.6 + 2.0 * speed)
    if rotq > 0.01 then
      local steps = lerp(64, 10, rotq)
      ang = (math.floor(ang * steps) / steps)
    end
    for i = 1, rings do
      local u = (i - 1) / math.max(1, (rings - 1))
      local r = lerp(6, 34, u)
      -- pulse brightens inner rings
      local pulse_boost = note_pulse * (1 - u) * 5
      -- audio-reactive brightness
      local audio_brighten = amp_level * 3
      screen.level(clamp(math.floor(lerp(2, 10, 1 - u) + pulse_boost + audio_brighten + 0.5), 1, 15))
      screen.circle(cx, cy, r)
      screen.stroke()
    end
    screen.level(10)
    screen.move(cx - 40, cy); screen.line(cx + 40, cy); screen.stroke()
    screen.move(cx, cy - 22); screen.line(cx, cy + 22); screen.stroke()
    local ticks = math.floor(lerp(8, 28, m) + 0.5)
    for i = 1, ticks do
      local a = ang + (i / ticks) * (math.pi * 2)
      local r1 = lerp(10, 18, tri(time * 0.3 + i * 0.07))
      local r2 = r1 + lerp(6, 16, m)
      screen.level((i % 3 == 0) and 15 or 6)
      screen.move(cx + math.cos(a) * r1, cy + math.sin(a) * r1)
      screen.line(cx + math.cos(a) * r2, cy + math.sin(a) * r2)
      screen.stroke()
    end
  end
}

-- 4) SPIRAL
anims[4] = {
  name = "SPIRAL",
  draw = function(time, m)
    local cx, cy = 64, 32
    local turns = lerp(1.0, 4.5, m)
    local steps = math.floor(lerp(40, 120, m) + 0.5)
    local spin = time * (0.8 + 2.2 * speed)
    local maxr = lerp(22, 40, m) + note_pulse * 6 + amp_level * 8
    for i = 1, steps do
      local u = i / steps
      local a = spin + u * turns * math.pi * 2
      local r = u * maxr
      local x = cx + math.cos(a) * r
      local y = cy + math.sin(a) * r
      local lvl = math.floor(lerp(15, 2, u) + 0.5)
      screen.level(lvl)
      screen.pixel(x, y)
    end
    screen.fill()
    local wedge = lerp(0.05, 0.25, m)
    local a0 = spin
    local a1 = spin + wedge * math.pi * 2
    screen.level(6)
    for r = 6, 40, 4 do
      screen.move(cx + math.cos(a0) * r, cy + math.sin(a0) * r)
      screen.line(cx + math.cos(a1) * r, cy + math.sin(a1) * r)
      screen.stroke()
    end
  end
}

-- 5) ORBITS
anims[5] = {
  name = "ORBITS",
  draw = function(time, m)
    local cx, cy = 64, 32
    local n = math.floor(lerp(6, 18, m) + 0.5)
    local spread = lerp(10, 30, m) + note_pulse * 8 + amp_level * 12
    local wob = lerp(0.0, 0.8, m)
    local trail = math.floor(lerp(2, 6, m) + 0.5)
    for ti = trail, 0, -1 do
      local tt = time - (ti / (fps * 0.75))
      local lvl = math.floor(lerp(3, 15, 1 - (ti / math.max(1, trail))) + 0.5)
      screen.level(lvl)
      for i = 1, n do
        local a = tt * (0.6 + 1.8 * speed) + i * (math.pi * 2 / n)
        local rr = spread + math.sin(tt * 0.7 + i) * (spread * 0.25)
        rr = rr + wob * math.sin(tt * 5 + i * 0.3) * 6
        local x = cx + math.cos(a) * rr
        local y = cy + math.sin(a * (1.0 + 0.15 * wob)) * (rr * 0.65)
        screen.pixel(x, y)
      end
      screen.fill()
    end
    screen.level(8)
    screen.circle(cx, cy, 2 + 2 * tri(time * (0.8 + speed)))
    screen.stroke()
  end
}

-- 6) SHUTTER
anims[6] = {
  name = "SHUTTER",
  draw = function(time, m)
    local w, h = 128, 64
    local p = (time * (0.5 + 1.8 * speed)) % 1.0
    local k = ease_punch(p)
    local bars = math.floor(lerp(4, 14, m) + 0.5)
    local gap = h / bars
    local shake = lerp(0.0, 2.5, m) + note_pulse * 3 + amp_level * 2
    local sx = math.sin(time * 23.1) * shake
    local sy = math.cos(time * 19.8) * shake * 0.6
    for i = 0, bars - 1 do
      local y0 = i * gap
      local open = lerp(0.2, 1.0, m) * (1 - k)
      local bh = gap * open
      local lvl = (i % 2 == 0) and 12 or 5
      screen.level(lvl)
      screen.rect(0 + sx, y0 + sy, w, bh)
      screen.fill()
    end
    screen.level(15)
    local yy = lerp(4, 60, p)
    screen.move(0, yy); screen.line(127, yy); screen.stroke()
  end
}

-- 7) MOSAIC
anims[7] = {
  name = "MOSAIC",
  draw = function(time, m)
    local w, h = 128, 64
    local zoom = lerp(1.0, 3.2, m)
    -- performance guard: min block size of 4 to avoid frame drops
    local block = math.max(math.floor(lerp(8, 2, m) + 0.5), 4)
    local freq = (0.35 + 1.7 * speed)
    -- note pulse shifts the wave phase for a visual "kick"
    local pulse_offset = note_pulse * 2.0
    -- audio-reactive frequency modulation
    local audio_freq_mod = amp_level * 3.0
    for y = 0, h - 1, block do
      for x = 0, w - 1, block do
        local nx = (x - 64) / 64
        local ny = (y - 32) / 32
        local r = math.sqrt(nx * nx + ny * ny)
        local v = math.sin((r * (7.0 + audio_freq_mod) * zoom) - time * freq * 6.0 + pulse_offset)
        local vv = (v * 0.5 + 0.5)
        local lvl = math.floor(lerp(2, 15, vv) + 0.5)
        screen.level(lvl)
        screen.rect(x, y, block, block)
        screen.fill()
      end
    end
    local yy = (time * (0.6 + 1.2 * speed) * 64) % 64
    screen.level(5)
    screen.rect(0, yy, 128, 2)
    screen.fill()
  end
}

-- 8) WAVES
anims[8] = {
  name = "WAVES",
  draw = function(time, m)
    local h = 64
    local bands = math.floor(lerp(6, 20, m) + 0.5)
    local amp = lerp(1.0, 6.0, m) + note_pulse * 4 + amp_level * 8
    local rate = (0.6 + 2.0 * speed)
    for i = 1, bands do
      local yy = (i / (bands + 1)) * h
      local ph = time * rate + i * 0.35
      local off = math.sin(ph) * amp + math.sin(ph * 2.1) * (amp * 0.35)
      local lvl = (i % 3 == 0) and 12 or ((i % 2 == 0) and 6 or 3)
      screen.level(lvl)
      screen.move(0, yy + off)
      screen.line(127, yy - off)
      screen.stroke()
    end
    local cx, cy = 64, 32
    local p = (time * (0.4 + 1.4 * speed)) % 1.0
    local punch = ease_punch(p)
    local r = lerp(6, 36, m) * punch
    screen.level(math.floor(lerp(2, 14, m) + 0.5))
    screen.circle(cx, cy, r)
    screen.stroke()
  end
}

-- 9) ESCHER MAZE (Truchet tiling) + pulse
anims[9] = {
  name = "ESCHER",
  draw = function(time, m)
    local w, h = 128, 64
    local cell = math.floor(lerp(16, 8, m) + 0.5)
    local cols = math.floor(w / cell)
    local rows = math.floor(h / cell)
    local function hash01(x, y, s)
      local v = math.sin(x * 12.9898 + y * 78.233 + s * 37.719) * 43758.5453
      return v - math.floor(v)
    end
    local wx = (time * (0.35 + 1.2 * speed)) % cols
    local wy = (time * (0.22 + 0.9 * speed)) % rows
    local thick = (m > 0.55) and 2 or 1
    local flip_rate = lerp(0.03, 0.25, m)
    -- note pulse widens the glow radius
    local glow_boost = note_pulse * 2.0 + amp_level * 1.5
    for gy = 0, rows - 1 do
      for gx = 0, cols - 1 do
        local x0 = gx * cell
        local y0 = gy * cell
        local s = time * flip_rate
        local r = hash01(gx, gy, s)
        local orient = (r > 0.5)
        local dx = gx - wx
        local dy = gy - wy
        local d = math.sqrt(dx * dx + dy * dy)
        local glow = clamp(1.0 - d / (lerp(2.0, 4.5, m) + glow_boost), 0.0, 1.0)
        local lvl = math.floor(lerp(3, 15, glow) + 0.5)
        screen.level(lvl)
        if orient then
          for k = 1, thick do
            screen.arc(x0, y0, cell - k, 0, math.pi / 2); screen.stroke()
            screen.arc(x0 + cell, y0 + cell, cell - k, math.pi, 3 * math.pi / 2); screen.stroke()
          end
        else
          for k = 1, thick do
            screen.arc(x0 + cell, y0, cell - k, math.pi / 2, math.pi); screen.stroke()
            screen.arc(x0, y0 + cell, cell - k, 3 * math.pi / 2, 2 * math.pi); screen.stroke()
          end
        end
      end
    end
  end
}

-- 10) INFINITE STAIR MAZE (isometric loop vibe)
anims[10] = {
  name = "STAIRS",
  draw = function(time, m)
    local cx, cy = 64, 22
    local cell = math.floor(lerp(10, 6, m) + 0.5)
    local cols = 9
    local rows = 7
    local function iso(i, j)
      local x = cx + (i - j) * cell
      local y = cy + (i + j) * (cell * 0.55)
      return x, y
    end
    local ph = time * (0.35 + 1.3 * speed)
    local q = lerp(1, 6, m)
    local stair_phase = ph
    if m > 0.55 then stair_phase = math.floor(ph * q) / q end
    local function height(i, j)
      local v = (i + j + stair_phase * 2.0)
      return v - math.floor(v)
    end
    -- note pulse adds global brightness boost
    local pulse_boost = math.floor(note_pulse * 4 + 0.5)
    local audio_boost = math.floor(amp_level * 3 + 0.5)
    for j = rows, 0, -1 do
      for i = 0, cols do
        local x, y = iso(i, j)
        local h0 = height(i, j)
        local top = clamp(math.floor(lerp(4, 10, 1 - h0) + pulse_boost + audio_boost + 0.5), 1, 15)
        local edge1 = clamp(math.floor(lerp(2, 8, 1 - h0) + pulse_boost + audio_boost + 0.5), 1, 15)
        local edge2 = clamp(math.floor(lerp(1, 6, 1 - h0) + pulse_boost + audio_boost + 0.5), 1, 15)
        local x1, y1 = x, y - cell * 0.55
        local x2, y2 = x + cell, y
        local x3, y3 = x, y + cell * 0.55
        local x4, y4 = x - cell, y
        screen.level(top)
        screen.move(x1, y1)
        screen.line(x2, y2)
        screen.line(x3, y3)
        screen.line(x4, y4)
        screen.line(x1, y1)
        screen.fill()
        screen.level(edge2)
        screen.move(x4, y4); screen.line(x3, y3); screen.stroke()
        screen.level(edge1)
        screen.move(x2, y2); screen.line(x3, y3); screen.stroke()
        if m > 0.25 then
          local wall = (math.sin(i * 12.3 + j * 7.7 + ph * 1.2) * 0.5 + 0.5)
          if wall > lerp(0.85, 0.55, m) then
            screen.level(15)
            screen.move(x1, y1); screen.line(x2, y2); screen.stroke()
          end
        end
      end
    end
    screen.level(math.floor(lerp(2, 8, m) + 0.5))
    screen.move(0, 32); screen.line(127, 32); screen.stroke()
  end
}

-- 11) RECURSIVE CORRIDOR (Droste-ish)
anims[11] = {
  name = "CORRIDOR",
  draw = function(time, m)
    local w, h = 128, 64
    local depth = math.floor(lerp(6, 14, m) + 0.5)
    local skew = lerp(0.0, 10.0, m)
    local wob = lerp(0.0, 2.5, m) + note_pulse * 2 + amp_level * 1.5
    local ox = math.sin(time * (0.6 + 1.5 * speed)) * wob
    local oy = math.cos(time * (0.5 + 1.2 * speed)) * wob
    local x0, y0 = 6 + ox, 6 + oy
    local x1, y1 = w - 7 + ox, h - 7 + oy
    for k = 1, depth do
      local u = (k - 1) / math.max(1, depth - 1)
      local lvl = math.floor(lerp(15, 2, u) + 0.5)
      screen.level(lvl)
      local inset = k * lerp(2.5, 3.5, m)
      local sx0 = x0 + inset + u * skew
      local sy0 = y0 + inset
      local sx1 = x1 - inset
      local sy1 = y1 - inset - u * skew
      screen.rect(sx0, sy0, (sx1 - sx0), (sy1 - sy0))
      screen.stroke()
      if m > 0.55 and (k % 2 == 0) then
        screen.level(math.floor(lerp(4, 12, m) + 0.5))
        screen.move(sx0, sy0); screen.line(sx1, sy1); screen.stroke()
      end
      local shimmer = (time * (0.9 + 2.0 * speed) + u * 6.0) % 1.0
      local yy = sy0 + shimmer * (sy1 - sy0)
      screen.level(2 + math.floor(6 * (1 - u)))
      screen.move(sx0, yy); screen.line(sx1, yy); screen.stroke()
    end
  end
}

-- ======================
-- Sound: sequences (drunk walk)
-- ======================
local function generate_seq(anim_idx)
  local steps = params:get("steps")
  local lo = params:get("oct_lo")
  local hi = params:get("oct_hi")
  local s = {}
  -- start near center of range
  local oct = clamp(0, lo, hi)
  for i = 1, steps do
    s[i] = oct
    -- drunk walk: stay, +1, or -1, biased toward center
    local r = math.random()
    local drift = 0
    if r < 0.35 then
      drift = 0  -- stay (35%)
    elseif r < 0.55 then
      drift = -1 -- down (20%)
    elseif r < 0.75 then
      drift = 1  -- up (20%)
    elseif oct > 0 then
      drift = -1 -- gravity toward 0 when high (12.5%)
    elseif oct < 0 then
      drift = 1  -- gravity toward 0 when low (12.5%)
    end
    -- occasional wider leap for surprise
    if math.random() < 0.08 then
      drift = drift * 2
    end
    oct = clamp(oct + drift, lo, hi)
  end
  seqs[anim_idx] = s
end

local function ensure_seqs()
  for i = 1, #anims do
    if seqs[i] == nil then generate_seq(i) end
  end
end

local function set_current_anim(i)
  i = clamp(i, 1, #anims)
  if i ~= current_anim then
    current_anim = i
    step_i = 1
    if seqs[current_anim] == nil then generate_seq(current_anim) end
  end
end

local function sync_division()
  -- convert division param to clock.sync value
  -- 1 = 1/4 note, 2 = 1/8 note, 3 = 1/16 note
  local div = params:get("division")
  if div == 1 then return 1
  elseif div == 2 then return 1/2
  else return 1/4
  end
end

local function play_step()
  local base_note = params:get("base_note")
  local s = seqs[current_anim]
  if not s or #s == 0 then return end
  local oct = s[step_i] or 0
  local note = base_note + 12 * oct
  engine.amp(params:get("amp"))
  engine.release(params:get("rel"))
  engine.cutoff(params:get("cutoff"))
  engine.hz(musicutil.note_num_to_freq(note))
  -- fire visual pulse
  note_pulse = 1.0
  step_i = step_i + 1
  if step_i > #s then step_i = 1 end
end

local function sequencer()
  while true do
    clock.sync(sync_division())
    if playing then
      play_step()
    end
  end
end

-- ======================
-- MIDI input
-- ======================
local midi_in = midi.connect(1)

local function handle_midi_note_on(note, velocity)
  midi_burst_active = true
  midi_burst_intensity = velocity / 127.0
  -- decay burst over 150ms
  clock.run(function()
    for _ = 1, 15 do
      clock.sleep(0.01)
      midi_burst_intensity = midi_burst_intensity * 0.92
    end
    midi_burst_active = false
  end)
end

if midi_in then
  midi_in.note_on = handle_midi_note_on
end

-- ======================
-- Norns lifecycle
-- ======================
local metro_redraw = metro.init()

function init()
  math.randomseed(os.time())

  -- params
  params:add_separator("opxy_viz", "OPXY VIZ")

  params:add_option("fps", "FPS", { "30", "60" }, 1)
  params:set_action("fps", function(v)
    fps = (v == 2) and 60 or 30
    metro_redraw.time = 1 / fps
  end)

  params:add_control("morph", "MORPH (enc2)", controlspec.new(0.0, 1.0, "lin", 0.001, morph))
  params:set_action("morph", function(v) morph = v end)

  params:add_control("speed", "SPEED (enc3)", controlspec.new(0.2, 2.0, "lin", 0.01, speed, "x"))
  params:set_action("speed", function(v) speed = v end)

  params:add_separator("sound", "SOUND")
  params:add_control("bpm", "BPM", controlspec.new(40, 180, "lin", 1, 90, "bpm"))
  params:add_option("division", "STEP DIV", { "1/4", "1/8", "1/16" }, 3)
  params:add_number("steps", "STEPS", 4, 32, 16)
  params:add_number("base_note", "BASE MIDI", 24, 60, 36)
  params:add_number("oct_lo", "OCT LOW", -3, 0, -1)
  params:add_number("oct_hi", "OCT HIGH", 0, 3, 1)
  params:add_control("amp", "AMP", controlspec.new(0.0, 1.0, "lin", 0.01, 0.35))
  params:add_control("rel", "RELEASE", controlspec.new(0.05, 3.0, "lin", 0.01, 0.6, "s"))
  params:add_control("cutoff", "CUTOFF", controlspec.new(80, 4000, "exp", 1, 700, "hz"))

  params:add_separator("audio_reactive", "AUDIO REACTIVE")
  params:add_option("audio_reactive", "AUDIO REACTIVE", { "off", "on" }, 1)
  params:set_action("audio_reactive", function(v) audio_reactive = (v == 2) end)

  params:bang()
  ensure_seqs()
  set_current_anim(1)

  -- start sequencer (uses clock.sync for external sync support)
  clock.run(sequencer)

  -- redraw metro
  last_time = util.time()
  metro_redraw.time = 1 / fps
  metro_redraw.event = function()
    local now = util.time()
    local dt = now - last_time
    last_time = now
    t = t + dt
    -- decay note pulse each frame
    note_pulse = note_pulse * note_pulse_decay
    if note_pulse < 0.01 then note_pulse = 0 end
    -- smooth audio level (low-pass filter)
    amp_smooth = amp_smooth * 0.85 + amp_level * 0.15
    redraw()
  end
  metro_redraw:start()

  -- audio polling metro
  local audio_metro = metro.init()
  audio_metro.time = 0.1
  audio_metro.event = function()
    if audio_reactive then
      poll_audio_level()
    end
  end
  audio_metro:start()
end

function enc(n, d)
  if n == 1 then
    sel = clamp(sel + d / 75, 1.0, #anims)
    set_current_anim(math.floor(sel))
  elseif n == 2 then
    morph = clamp(morph + d / 80, 0.0, 1.0)
    params:set("morph", morph)
  elseif n == 3 then
    speed = clamp(speed + d / 80, 0.2, 2.0)
    params:set("speed", speed)
  end
end

function key(n, z)
  if z == 0 then return end
  if n == 2 then
    generate_seq(current_anim)
    step_i = 1
  elseif n == 3 then
    playing = not playing
  end
end

function redraw()
  screen.clear()

  -- determine which animation(s) to draw
  local i = math.floor(sel)
  local j = math.min(i + 1, #anims)
  local blend = sel - i

  -- temporal dithering crossfade: pick A or B each frame
  local show_idx
  if blend < 0.001 then
    show_idx = i
  elseif blend > 0.999 then
    show_idx = j
  elseif choose_temporal_mix(blend) then
    show_idx = j
  else
    show_idx = i
  end

  -- draw grain texture + selected animation directly to screen
  draw_grain(t, morph)
  anims[show_idx].draw(t, morph)

  -- note pulse: brief screen-wide brightness flash
  if note_pulse > 0.3 then
    screen.level(clamp(math.floor(note_pulse * 3), 1, 4))
    screen.rect(0, 0, 128, 1)
    screen.fill()
  end

  -- MIDI burst effect: temporary size increase on elements
  if midi_burst_active then
    screen.level(clamp(math.floor(midi_burst_intensity * 8), 2, 12))
    for _ = 1, 3 do
      screen.circle(64, 32, 20 + midi_burst_intensity * 10)
      screen.stroke()
    end
  end

  -- label + sound status
  screen.level(6)
  screen.move(2, 62)
  screen.text(anims[show_idx].name)
  screen.move(92, 62)
  screen.text(playing and "PLAY" or "STOP")

  -- audio reactive indicator
  if audio_reactive then
    screen.level(clamp(math.floor(amp_smooth * 12) + 3, 2, 15))
    screen.move(64, 62)
    screen.text_center("AUDIO")
  end

  screen.update()
end

function cleanup()
  clock.cancel_all()
  if metro_redraw then metro_redraw:stop() end
end
