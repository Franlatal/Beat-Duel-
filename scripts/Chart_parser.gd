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
##   "sections": Array[Dict],         # [{name, time (sec)}, ...] from [Events] "section X"
##   "lyrics": Array[Dict],           # sung lines, see below
## }
##
## Lyrics come from the [Events] lyric / phrase_start / phrase_end events
## Moonscraper writes. Each entry of "lyrics" is one line to show:
##   {start (sec), end (sec), section (String), syllables: [{time, end, text}, ...]}
## A syllable's text already carries its trailing space when the next
## syllable is a new word, so a line's text is just the syllables joined.
## Charters often wrap a whole verse in a single phrase, so phrases are
## split further into singable lines (see _starts_new_lyric_line).
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
				_try_parse_segment_event(ev, resolution, tempo_events, offset, segments)

	# Fallback: if the chosen difficulty track didn't repeat the "E segmentN"
	# markers, read them from [Events] or another difficulty section so
	# charters only need to place segment markers once per song.
	if segments.is_empty():
		for fallback_sec in ["Events", "ExpertSingle", "HardSingle", "MediumSingle", "EasySingle"]:
			if fallback_sec == track_name or not sections.has(fallback_sec):
				continue
			for line in sections[fallback_sec]:
				var ev := _parse_event_line(line)
				if not ev.is_empty() and ev.type == "E" and not ev.args.is_empty():
					_try_parse_segment_event(ev, resolution, tempo_events, offset, segments)
			if not segments.is_empty():
				break

	notes.sort_custom(func(a, b): return a.time < b.time)
	segments.sort_custom(func(a, b): return a.time < b.time)

	# Lyrics and sections are global, so they live in [Events] whatever
	# difficulty is being played.
	var song_sections: Array = []
	var lyrics: Array = []
	if sections.has("Events"):
		song_sections = _parse_sections(sections["Events"], resolution, tempo_events, offset)
		lyrics = _parse_lyrics(sections["Events"], resolution, tempo_events, offset)
		for line in lyrics:
			line["section"] = _section_at(song_sections, line.start)

	# Seconds (offset applied) for each tempo change, so beat-synced visuals
	# like the lyric pulse can find the beat without tick math.
	for te in tempo_events:
		te["time"] = _tick_to_seconds(te.tick, resolution, tempo_events) + offset

	return {
		"resolution": resolution,
		"offset": offset,        # seconds, from [Song] "Offset" — already applied to the times below
		"tempo_events": tempo_events,   # [{tick, bpm, time}, ...]
		"notes": notes,
		"segments": segments,   # [{tick, index, time}, ...] sorted by time
		"sections": song_sections,
		"lyrics": lyrics,
	}

# --- lyrics -----------------------------------------------------------

## Lines longer than this many characters are split in two at their most
## natural word break.
const LYRIC_MAX_LINE_CHARS := 40
## A pause this long (in beats) between words always starts a new line.
const LYRIC_BREAK_GAP_BEATS := 4.0
## A pause this long (in beats) starts a new line when the next word is
## capitalized, which is how sung lines usually begin.
const LYRIC_CAPITAL_GAP_BEATS := 2.0
## The last syllable of a line counts as sung for at most this long.
const LYRIC_MAX_SYLLABLE_SEC := 1.0
## Words that are capitalized mid-line and so never start a line on their own.
const LYRIC_ALWAYS_CAPITAL := ["I", "I'm", "I'll", "I'd", "I've"]

func _parse_sections(event_lines: Array, resolution: int, tempo_events: Array, offset: float) -> Array:
	var result: Array = []
	for line in event_lines:
		var ev := _parse_event_line(line)
		if ev.is_empty() or ev.type != "E" or ev.args.is_empty():
			continue
		var label := _event_label(ev.args)
		if label.begins_with("section "):
			result.append({
				"name": label.substr("section ".length()).strip_edges(),
				"time": _tick_to_seconds(ev.tick, resolution, tempo_events) + offset,
			})
	result.sort_custom(func(a, b): return a.time < b.time)
	return result

func _section_at(song_sections: Array, time: float) -> String:
	var found := ""
	for sec in song_sections:
		if sec.time <= time + 0.001:
			found = sec.name
		else:
			break
	return found

func _parse_lyrics(event_lines: Array, resolution: int, tempo_events: Array, offset: float) -> Array:
	# Collect lyric events, ordered so that at the same tick a phrase_end
	# closes the old phrase before a phrase_start opens the next one, and
	# both come before that tick's lyric.
	var events: Array = []
	for line in event_lines:
		var ev := _parse_event_line(line)
		if ev.is_empty() or ev.type != "E" or ev.args.is_empty():
			continue
		var label := _event_label(ev.args)
		if label == "phrase_end":
			events.append({"tick": ev.tick, "order": 0, "kind": "end"})
		elif label == "phrase_start":
			events.append({"tick": ev.tick, "order": 1, "kind": "start"})
		elif label.begins_with("lyric "):
			events.append({"tick": ev.tick, "order": 2, "kind": "lyric", "raw": label.substr("lyric ".length())})
	events.sort_custom(func(a, b): return a.tick < b.tick or (a.tick == b.tick and a.order < b.order))

	var lines: Array = []
	var current: Array = []       # syllables of the line being built
	var prev: Dictionary = {}     # previous syllable in the current line
	for e in events:
		var time := _tick_to_seconds(e.tick, resolution, tempo_events) + offset
		if e.kind != "lyric":
			_close_lyric_line(lines, current, time, resolution)
			current = []
			prev = {}
			continue

		var syl := _clean_lyric(e.raw)
		if syl.is_empty():
			continue   # pitch slide ("+") or a marker-only event: nothing to show
		syl["tick"] = e.tick
		syl["time"] = time
		if not prev.is_empty() and _starts_new_lyric_line(prev, syl, resolution):
			_close_lyric_line(lines, current, time, resolution)
			current = []
		current.append(syl)
		prev = syl
	_close_lyric_line(lines, current, INF, resolution)
	return lines

## Turns one raw lyric into {text, joins_next}, following the Rock Band /
## Clone Hero conventions Moonscraper uses: a trailing "-" joins the next
## syllable into the same word, "=" is a hyphen that stays visible, "_"
## is a space, and "#" "^" "*" "%" "$" are pitch/style markers that are
## never shown. Returns {} for a "+" (pitch slide on the last syllable).
func _clean_lyric(raw: String) -> Dictionary:
	var text := raw.strip_edges()
	if text == "+" or text == "":
		return {}
	for marker in ["#", "^", "*", "%", "$", "+"]:
		text = text.replace(marker, "")
	var joins_next := false
	if text.ends_with("-"):
		joins_next = true
		text = text.substr(0, text.length() - 1)
	elif text.ends_with("="):
		joins_next = true
		text = text.substr(0, text.length() - 1) + "-"
	text = text.replace("=", "-").replace("_", " ").replace("§", " ").strip_edges()
	if text == "":
		return {}
	return {"text": text, "joins_next": joins_next}

func _starts_new_lyric_line(prev: Dictionary, syl: Dictionary, resolution: int) -> bool:
	if prev.joins_next:
		return false   # never split a word
	var gap_beats := float(syl.tick - prev.tick) / float(resolution)
	if gap_beats >= LYRIC_BREAK_GAP_BEATS:
		return true
	return gap_beats >= LYRIC_CAPITAL_GAP_BEATS and _starts_with_capital(syl.text)

func _starts_with_capital(text: String) -> bool:
	var first_word: String = text.split(" ")[0].rstrip(",.!?;:")
	if first_word.is_empty() or first_word in LYRIC_ALWAYS_CAPITAL:
		return false
	return first_word[0] != first_word[0].to_lower()

## Characters a run of syllables takes on screen, spaces between words included.
func _lyric_length(syllables: Array) -> int:
	var length := 0
	for i in range(syllables.size()):
		length += String(syllables[i].text).length()
		if i < syllables.size() - 1 and not syllables[i].joins_next:
			length += 1
	return length

## Where to split a too-long line: the word break that looks most like
## the end of a sung line (a long pause, a capitalized next word, halves
## of similar length). Returns the first syllable of the second half, or
## -1 when the line is a single word.
func _best_lyric_split(syllables: Array, resolution: int) -> int:
	var total := _lyric_length(syllables)
	var best := -1
	var best_score := -INF
	for i in range(1, syllables.size()):
		if syllables[i - 1].joins_next:
			continue
		var gap_beats := float(syllables[i].tick - syllables[i - 1].tick) / float(resolution)
		var left := _lyric_length(syllables.slice(0, i))
		var right := total - left - 1
		var score := gap_beats - absf(float(left - right)) / float(LYRIC_MAX_LINE_CHARS)
		if _starts_with_capital(syllables[i].text):
			score += 2.0
		if score > best_score:
			best_score = score
			best = i
	return best

## Finishes a line: fills in each syllable's end time and its display
## text (with the space before the next word), then stores it.
## next_time is when whatever follows the line happens (next line or
## phrase_end), which caps how long the last syllable lasts.
func _close_lyric_line(lines: Array, syllables: Array, next_time: float, resolution: int) -> void:
	if syllables.is_empty():
		return
	if _lyric_length(syllables) > LYRIC_MAX_LINE_CHARS:
		var cut := _best_lyric_split(syllables, resolution)
		if cut > 0:
			_close_lyric_line(lines, syllables.slice(0, cut), syllables[cut].time, resolution)
			_close_lyric_line(lines, syllables.slice(cut), next_time, resolution)
			return
	var out: Array = []
	for i in range(syllables.size()):
		var s: Dictionary = syllables[i]
		var is_last := i == syllables.size() - 1
		var end_time: float = minf(next_time, s.time + LYRIC_MAX_SYLLABLE_SEC) if is_last else syllables[i + 1].time
		var text: String = s.text
		if not is_last and not s.joins_next:
			text += " "
		out.append({"time": s.time, "end": end_time, "text": text})
	lines.append({
		"start": out[0].time,
		"end": out[out.size() - 1].end,
		"section": "",
		"syllables": out,
	})

# --- internal helpers -------------------------------------------------

## Rebuilds the text of an "E" event from its space-split args, without
## surrounding quotes (e.g. E "lyric twen-" -> lyric twen-).
func _event_label(args) -> String:
	return " ".join(PackedStringArray(args)).strip_edges().lstrip("\"").rstrip("\"")

func _try_parse_segment_event(ev: Dictionary, resolution: int, tempo_events: Array, offset: float, segments: Array) -> void:
	# Strip quotes in case a section event in [Events] is formatted like: E "segment1"
	var label: String = String(ev.args[0]).lstrip("\"").rstrip("\"").to_lower()
	if label.begins_with("segment"):
		var num_str := label.substr("segment".length())
		if num_str.is_valid_int():
			segments.append({
				"tick": ev.tick,
				"index": int(num_str),
				"time": _tick_to_seconds(ev.tick, resolution, tempo_events) + offset,
			})

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
