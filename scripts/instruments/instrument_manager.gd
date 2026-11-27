extends Node
## Autoload: loads the instrument catalogue and tracks the selected instrument.

signal instrument_selected(def: InstrumentDef)
const CATALOG_DIR := "res://data/instruments/"
const CATALOG_PATH := "res://data/instruments/instruments.json"
const PRESETS_PATH := "res://data/presets/instrument_presets.json"

var instruments: Array[InstrumentDef] = []
var current: InstrumentDef


func _ready() -> void:
	_load_catalog()


## Loads data/instruments/instruments.json first, then every other *.json there.
## An entry whose id already exists REPLACES it (so packs can upgrade built-ins).
func _load_catalog() -> void:
	var presets := _load_presets()
	var files := [CATALOG_PATH]
	var dir := DirAccess.open(CATALOG_DIR)
	if dir:
		var extra := Array(dir.get_files()).filter(func(n: String): return n.ends_with(".json") and n != "instruments.json")
		extra.sort()
		for n in extra:
			files.append(CATALOG_DIR + n)
	for path in files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			push_error("InstrumentManager: cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("instruments"):
			push_error("InstrumentManager: malformed catalogue %s" % path)
			continue
		for d in parsed["instruments"]:
			var def := InstrumentDef.from_dict(d)
			if def.id == "" or def.synth == "":
				push_warning("InstrumentManager: skipping invalid entry %s" % str(d))
				continue
			def.presets = presets.get(def.id, [])
			var replaced := false
			for i in instruments.size():
				if instruments[i].id == def.id:
					instruments[i] = def
					replaced = true
			if not replaced:
				instruments.append(def)


func _load_presets() -> Dictionary:
	var merged := {}
	var paths := [PRESETS_PATH]
	var dir := DirAccess.open("res://data/presets/")
	if dir:
		for n in dir.get_files():
			if n.ends_with(".json") and ("res://data/presets/" + n) != PRESETS_PATH:
				paths.append("res://data/presets/" + n)
	for path in paths:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			merged.merge(parsed, true)
	return merged


## Older projects may still name instruments we removed; map them to the closest VSCO2 / drum kit id.
const ID_ALIASES := {
	"piano": "grand_piano",
	"salamander_grand": "grand_piano",
	"violin": "solo_violin",
	"strings": "violins",
	"guitar": "harp_real",
	"synth_lead": "flute",
	"guzheng": "harp_real",
	"erhu": "solo_violin",
	"dizi": "flute",
	"taiko": "bassdrum",
	"organ": "grand_piano",
	"pad": "violins",
	"choir": "violins",
	"brass": "trumpet",
	"braam": "tuba",
	"ostinato": "violins",
	"hybrid_lead": "flute",
	"pluck_synth": "harp_real",
	"bass808": "bassdrum",
	"epic_hit": "bassdrum",
	"epic_strings": "violins",
	"soaring_strings": "violins",
	"dark_strings": "cellos",
	"brass_braam": "tuba",
	"heroic_horns": "horn",
	"cinema_piano": "grand_piano",
	"trailer_hit": "bassdrum",
	"panda_flute": "flute",
	"panda_strings": "violins",
	"panda_zither": "harp_real",
}


func get_by_id(id: String) -> InstrumentDef:
	for def in instruments:
		if def.id == id:
			return def
	return null


## Resolve a saved / requested id to a live catalogue entry (alias → fallback).
func resolve_id(id: String) -> String:
	var mapped := str(ID_ALIASES.get(id, id))
	if get_by_id(mapped) != null:
		return mapped
	if get_by_id(id) != null:
		return id
	if get_by_id("grand_piano") != null:
		return "grand_piano"
	if get_by_id("kick") != null:
		return "kick"
	return instruments[0].id if not instruments.is_empty() else id


func get_or_default(id: String) -> InstrumentDef:
	return get_by_id(resolve_id(id))


func categories() -> PackedStringArray:
	var out := PackedStringArray()
	for def in instruments:
		if not out.has(def.category):
			out.append(def.category)
	return out


func select(id: String) -> void:
	var def := get_by_id(id)
	if def == null:
		push_warning("InstrumentManager: unknown instrument '%s'" % id)
		return
	current = def
	instrument_selected.emit(def)
