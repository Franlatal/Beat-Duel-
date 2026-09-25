class_name ChartParser
extends RefCounted

## Parses Moonscraper Chart Editor (.chart) files for use in Godot.
##
## Usage:
##   var parser := ChartParser.new()
##   var chart_data := parser.parse_file("res://charts/song.chart", "ExpertSingle")
##   for note in chart_data.notes:
##       print(note.time, " sec, lane ", note.lane)
##
## chart_data is a Dictionary:
## {
##   "resolution": int,               # ticks per quarter note
##   "offset": float,                 # seconds, from [Song] "Offset" — already applied below
##   "tempo_events": Array[Dict],     # [{tick, bpm}, ...] sorted by tick
##   "notes": Array[Dict],            # [{time (sec), lane (int), sustain (sec)}, ...] sorted by time
##   "segments": Array[Dict],         # [{tick, index (int), time (sec)}, ...] sorted by time,
##                                     # parsed from in-track "E segmentN" markers
## }
##
## "Offset" is applied as time = tick_time + offset: it shifts note/segment
## timestamps earlier (for a negative offset) or later (for a positive one),
## relative to wherever the audio actually starts playing (whether that's
## immediately, or after a pre-roll delay — see chart_player.gd, which uses
## a negative offset as exactly such a delay). This parser only computes the
## shifted timestamps; it doesn't decide when audio starts.
## (Confirmed against real chart data: a -3 offset moves a note charted at
## ~3.09s to ~0.09s relative to the audio's own start — i.e. right as the
## song begins, exactly what you'd expect from a charter using Offset to
## pull an early pickup note back to the beginning of the track.)
##
## Note: standard 5-fret charts use lanes 0-4 = Green/Red/Yellow/Blue/Orange.
## Lane 5 = forced flag, 6 = tap flag, 7 = open note (rules vary slightly by
## game/track type). This parser keeps all raw "N" events; filter/remap lanes
## 5-7 in your own game code depending on how many lanes you actually need.

func parse_file(path: String, track_name: String = "ExpertSingle") -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ChartParser: could not open '%s' (error %s)" % [path, FileAccess.get_open_error()])
		return {}
	var text := file.get_as_text()
	file.close()
	return parse_text(text, track_name)

func parse_text(text: String, track_name: String) -> Dictionary:
	var lines := text.split("\n")
	var sections := _split_sections(lines)

	var resolution := 192
	var offset := 0.0
	if sections.has("Song"):
		for line in sections["Song"]:
			var kv := _parse_kv(line)
			if kv.size() != 2:
				continue
			if kv[0] == "Resolution":
				resolution = int(kv[1])
			elif kv[0] == "Offset":
				offset = float(kv[1])

	var tempo_events: Array = []
	if sections.has("SyncTrack"):
		for line in sections["SyncTrack"]:
			var ev := _parse_event_line(line)
			if ev.is_empty():
				continue
			if ev.type == "B":
				tempo_events.append({"tick": ev.tick, "bpm": float(ev.args[0]) / 1000.0})
	tempo_events.sort_custom(func(a, b): return a.tick < b.tick)
	if tempo_events.is_empty():
		tempo_events.append({"tick": 0, "bpm": 120.0})
	elif tempo_events[0].tick != 0:
		tempo_events.insert(0, {"tick": 0, "bpm": tempo_events[0].bpm})

	var notes: Array = []
	var segments: Array = []
	if sections.has(track_name):
		for line in sections[track_name]:
			var ev := _parse_event_line(line)
			if ev.is_empty():
				continue
			if ev.type == "N":
				var lane := int(ev.args[0])
				var sustain_ticks := int(ev.args[1])
				var raw_time := _tick_to_seconds(ev.tick, resolution, tempo_events)
				var raw_end := _tick_to_seconds(ev.tick + sustain_ticks, resolution, tempo_events)
				notes.append({"time": raw_time + offset, "lane": lane, "sustain": raw_end - raw_time})
			elif ev.type == "E" and not ev.args.is_empty():
				# In-track text events, e.g. "1536 = E segment1", used here to
				# mark the start of each of the song's 3 gameplay segments.
				var label: String = String(ev.args[0]).to_lower()
				if label.begins_with("segment"):
					var num_str := label.substr("segment".length())
					if num_str.is_valid_int():
						segments.append({
							"tick": ev.tick,
							"index": int(num_str),
							"time": _tick_to_seconds(ev.tick, resolution, tempo_events) + offset,
						})
	notes.sort_custom(func(a, b): return a.time < b.time)
	segments.sort_custom(func(a, b): return a.time < b.time)

	return {
		"resolution": resolution,
		"offset": offset,        # seconds, from [Song] "Offset" — already applied to the times below
		"tempo_events": tempo_events,
		"notes": notes,
		"segments": segments,   # [{tick, index, time}, ...] sorted by time
	}

# --- internal helpers -------------------------------------------------

func _split_sections(lines: Array) -> Dictionary:
	var sections := {}
	var current_name := ""
	var current_lines: Array = []
	var in_section := false
	for raw_line in lines:
		var line: String = String(raw_line).strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			current_name = line.substr(1, line.length() - 2)
			current_lines = []
			continue
		if line == "{":
			in_section = true
			continue
		if line == "}":
			in_section = false
			if current_name != "":
				sections[current_name] = current_lines
			current_name = ""
			continue
		if in_section and line != "":
			current_lines.append(line)
	return sections

func _parse_kv(line: String) -> Array:
	var parts := line.split("=", false, 1)
	if parts.size() != 2:
		return []
	var value := parts[1].strip_edges().lstrip("\"").rstrip("\"")
	return [parts[0].strip_edges(), value]

func _parse_event_line(line: String) -> Dictionary:
	# Format: "<tick> = <TYPE> <arg1> <arg2> ..."
	var eq_index := line.find("=")
	if eq_index == -1:
		return {}
	var tick_str := line.substr(0, eq_index).strip_edges()
	var rest := line.substr(eq_index + 1).strip_edges()
	if not tick_str.is_valid_int():
		return {}
	var tokens := rest.split(" ", false)
	if tokens.is_empty():
		return {}
	return {
		"tick": int(tick_str),
		"type": tokens[0],
		"args": tokens.slice(1),
	}

func _tick_to_seconds(tick: int, resolution: int, tempo_events: Array) -> float:
	var time := 0.0
	for i in range(tempo_events.size()):
		var seg_start: int = tempo_events[i].tick
		var seg_bpm: float = tempo_events[i].bpm
		if tick <= seg_start:
			break
		var seg_end: int = tempo_events[i + 1].tick if i + 1 < tempo_events.size() else tick
		var calc_end: int = min(seg_end, tick)
		var ticks_in_segment: int = calc_end - seg_start
		if ticks_in_segment > 0:
			time += ticks_in_segment * (60.0 / (seg_bpm * resolution))
		if tick <= seg_end:
			break
	return time
