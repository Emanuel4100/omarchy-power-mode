function parseMonitorsJson(raw) {
  var list = []
  try {
    list = raw ? JSON.parse(String(raw)) : []
  } catch (e) {
    list = []
  }
  if (!Array.isArray(list)) return []

  return list.map(function(m) {
    return {
      name: String(m.name || ""),
      width: Number(m.width || 0),
      height: Number(m.height || 0),
      x: Number(m.x || 0),
      y: Number(m.y || 0),
      scale: Number(m.scale || 1),
      refreshRate: Number(m.refreshRate || 0),
      description: String(m.description || ""),
      availableModes: Array.isArray(m.availableModes) ? m.availableModes : []
    }
  })
}

function findMonitor(monitors, name) {
  for (var i = 0; i < monitors.length; i++) {
    if (monitors[i] && monitors[i].name === name) return monitors[i]
  }
  return null
}

// All resolutions a monitor actually supports, each with its own Hz list --
// unlike the single-resolution-only view this used to have, this covers
// external displays/TVs with several real resolutions, not just this
// machine's single-resolution laptop panel.
function modesFor(monitors, name) {
  var mon = findMonitor(monitors, name)
  if (!mon) return { resolutions: [], hzByResolution: {} }

  var resolutions = []
  var hzByResolution = {}

  for (var j = 0; j < mon.availableModes.length; j++) {
    var match = String(mon.availableModes[j]).match(/^(\d+)x(\d+)@([\d.]+)/)
    if (!match) continue
    var w = Number(match[1])
    var h = Number(match[2])
    var hz = Math.round(Number(match[3]))
    var res = w + "x" + h

    if (!hzByResolution[res]) {
      hzByResolution[res] = []
      resolutions.push(res)
    }
    if (hzByResolution[res].indexOf(hz) === -1) hzByResolution[res].push(hz)
  }

  resolutions.sort(function(a, b) {
    var pa = a.split("x"), pb = b.split("x")
    return (Number(pb[0]) * Number(pb[1])) - (Number(pa[0]) * Number(pa[1]))
  })
  for (var res2 in hzByResolution) {
    hzByResolution[res2].sort(function(a, b) { return b - a })
  }

  return { resolutions: resolutions, hzByResolution: hzByResolution }
}

function currentModeString(monitors, name) {
  var mon = findMonitor(monitors, name)
  if (!mon) return ""
  return mon.width + "x" + mon.height + "@" + Math.round(mon.refreshRate)
}

function parseModeString(mode) {
  var m = String(mode || "").match(/^(\d+)x(\d+)@(\d+(?:\.\d+)?)/)
  if (!m) return null
  return { width: Number(m[1]), height: Number(m[2]), hz: Math.round(Number(m[3])) }
}

function resolutionOf(mode) {
  var parsed = parseModeString(mode)
  return parsed ? parsed.width + "x" + parsed.height : ""
}

// Both end up inside Lua source for `hyprctl eval`, which Hyprland runs with
// the user's full privileges, so anything read back from settings.json has
// to be a plain number / plain output name before it gets anywhere near it.
function isValidScale(scale) {
  return /^\d+(\.\d+)?$/.test(String(scale || "")) && Number(scale) > 0
}

function isValidOutputName(name) {
  return /^[A-Za-z0-9._-]+$/.test(String(name || ""))
}

// ---------------------------------------------------------- scale presets

var SCALE_PRESETS = ["1", "1.25", "1.6", "2", "3", "4"]

function gcd(a, b) {
  while (b) {
    var r = a % b
    a = b
    b = r
  }
  return a
}

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

// Snaps a requested scale to one Hyprland will actually accept for this
// resolution (same approach Omarchy's own Display panel uses), so an
// arbitrary preset doesn't get silently rejected on an odd resolution.
function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var w = Number(width), h = Number(height)
  if (!isFinite(requested) || !isFinite(w) || !isFinite(h) || requested <= 0 || w <= 0 || h <= 0) return ""

  var divisor = gcd(Math.round(w * 120), Math.round(h * 120))
  var units = Math.round(requested * 120)
  if (units > divisor) units = divisor
  while (units > 0 && divisor % units !== 0) units++
  return normalizeScale(units / 120)
}

function scaleOptionsFor(width, height) {
  var seen = {}
  var out = []
  for (var i = 0; i < SCALE_PRESETS.length; i++) {
    var cleaned = cleanScale(SCALE_PRESETS[i], width, height)
    if (!cleaned || seen[cleaned]) continue
    seen[cleaned] = true
    out.push(cleaned)
  }
  return out
}

// ---------------------------------------------------------- power profiles

function parseProfiles(raw) {
  var lines = String(raw || "").split("\n")
  var list = []
  var active = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return { profiles: list, activeProfile: active }
}

function profileLabel(name) {
  var s = String(name || "")
  if (!s) return ""
  return s.charAt(0).toUpperCase() + s.slice(1).replace(/-/g, " ")
}

if (typeof module !== "undefined") {
  module.exports = {
    parseMonitorsJson: parseMonitorsJson,
    findMonitor: findMonitor,
    modesFor: modesFor,
    currentModeString: currentModeString,
    parseModeString: parseModeString,
    resolutionOf: resolutionOf,
    normalizeScale: normalizeScale,
    cleanScale: cleanScale,
    scaleOptionsFor: scaleOptionsFor,
    parseProfiles: parseProfiles,
    profileLabel: profileLabel
  }
}
