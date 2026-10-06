class_name ShipFrame
extends RefCounted
## The standard coordinate frame every ship is built in.
##
##   Origin  : midships (station 10 of 20), on the centerline, at the design waterline (DWL).
##   +Z      : toward the bow.        -Z : toward the stern.
##   +X      : to PORT (the engine's right-handed axes: looking toward +Z, +X is on the left).
##   +Y      : up.   y = 0 is the waterline, y = -draft is the keel, y = +freeboard is the main deck.
##   Units   : metres.
##
## Longitudinal positions can be given as a naval-architecture STATION (0 = after perpendicular,
## 10 = midships, 20 = forward perpendicular), as a FRACTION of length from midships
## (-0.5 stern .. +0.5 bow; what the rosters use), or as metres.
##
## Vertical positions are named DECKS, so the same description works for a destroyer and a
## battleship:  keel, inner_bottom, platform, main (weather deck), d01, d02, d03 ...
## A compartment is a box between two decks (or heights), at a position and width.
## Everything is derived from the roster entry, so the scale of a ship drives the layout.

var length: float
var beam: float
var draft: float
var freeboard: float
var deck_height: float                  ## height of one superstructure deck
var decks: Dictionary = {}              ## name -> y (metres above waterline)


static func for_entry(e: Dictionary) -> ShipFrame:
	var f := ShipFrame.new()
	f.length = e["length_m"]
	f.beam = e["beam_m"]
	f.draft = e["draft_m"]
	var fb_ratio := 0.03
	match String(e.get("type", "")):
		"carrier":
			fb_ratio = 0.055
		"motor_torpedo_boat":
			fb_ratio = 0.045
		"submarine":
			fb_ratio = 0.02
	f.freeboard = clampf(f.length * fb_ratio, 1.6, 15.0)
	f.deck_height = clampf(f.length * 0.011, 2.2, 3.2)
	f.decks = {
		"keel": -f.draft,
		"inner_bottom": -f.draft * 0.86,
		"platform": -f.draft * 0.5,
		"waterline": 0.0,
		"main": f.freeboard,
	}
	for i in range(1, 7):
		f.decks["d%02d" % i] = f.freeboard + f.deck_height * i
	return f


# --- Longitudinal --------------------------------------------------------------------

func z_station(station: float) -> float:
	return (station - 10.0) / 20.0 * length


func z_frac(frac_from_midships: float) -> float:
	return frac_from_midships * length


func station_of(z: float) -> float:
	return 10.0 + z / length * 20.0


# --- Vertical --------------------------------------------------------------------------

func deck(name_or_height) -> float:
	if name_or_height is String:
		return decks[name_or_height]
	return float(name_or_height)


# --- Hull form -------------------------------------------------------------------------

## Half-breadth of the hull (metres) at longitudinal position z, at the waterline.
## A parallel mid-body, a fine bow and a fuller stern ending in a transom.
func half_breadth(z: float) -> float:
	var u := clampf(z / (length * 0.5), -1.0, 1.0)      # -1 stern .. +1 bow
	var hb := beam * 0.5
	if u > 0.3:
		var t := (u - 0.3) / 0.7
		return maxf(hb * (1.0 - pow(t, 1.7)), hb * 0.05)
	if u < -0.5:
		var t2 := (-u - 0.5) / 0.5
		return hb * (1.0 - 0.45 * t2 * t2)
	return hb


# --- Spaces ------------------------------------------------------------------------------

## A box from z0..z1 (metres, forward positive), between two decks/heights, centred at x
## (port positive) with total `width`. Returns {"center": Vector3, "half": Vector3}.
func space(z0: float, z1: float, lo, hi, x: float, width: float) -> Dictionary:
	var zl := minf(z0, z1)
	var zh := maxf(z0, z1)
	var y0 := deck(lo)
	var y1 := deck(hi)
	return {
		"center": Vector3(x, (y0 + y1) * 0.5, (zl + zh) * 0.5),
		"half": Vector3(width * 0.5, absf(y1 - y0) * 0.5, (zh - zl) * 0.5),
	}


## Same, but given as centre + length.
func space_at(z: float, length_m: float, lo, hi, x: float, width: float) -> Dictionary:
	return space(z - length_m * 0.5, z + length_m * 0.5, lo, hi, x, width)
