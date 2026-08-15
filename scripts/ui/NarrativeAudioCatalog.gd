class_name NarrativeAudioCatalog
extends RefCounted

const CUE_LINE_ENGAGE := "narrative_line_engage"
const CUE_RADIO_CHANNEL_OPEN := "narrative_radio_channel_open"
const CUE_RADIO_CHANNEL_FADE := "narrative_radio_channel_fade"
const CUE_RADIO_DISTANT_CHANNEL := "narrative_radio_distant_channel"
const CUE_PUMPS_EMERGENCY := "narrative_pumps_emergency"
const CUE_PUMPS_STABLE := "narrative_pumps_stable"
const CUE_ARCHIVE_RELAY_READ := "narrative_archive_relay_read"
const CUE_R3_STARTUP := "narrative_r3_startup"
const CUE_C4_SINGLE_LINE := "narrative_c4_single_line"
const CUE_SPLITTER_BENCH_LATCH := "narrative_splitter_bench_latch"
const CUE_C4_DUAL_LINE_TEST := "narrative_c4_dual_line_test"
const CUE_C4_DUAL_LINE_STORM := "narrative_c4_dual_line_storm"
const CUE_FRONT_PRESSURE := "narrative_front_pressure"

const _STREAM_PATHS := {
	CUE_LINE_ENGAGE: "res://assets/audio/narrative/line_engage.wav",
	CUE_RADIO_CHANNEL_OPEN: "res://assets/audio/narrative/radio_channel_open.wav",
	CUE_RADIO_CHANNEL_FADE: "res://assets/audio/narrative/radio_channel_fade.wav",
	CUE_RADIO_DISTANT_CHANNEL: "res://assets/audio/narrative/radio_distant_channel.wav",
	CUE_PUMPS_EMERGENCY: "res://assets/audio/narrative/pumps_emergency.wav",
	CUE_PUMPS_STABLE: "res://assets/audio/narrative/pumps_stable.wav",
	CUE_ARCHIVE_RELAY_READ: "res://assets/audio/narrative/archive_relay_read.wav",
	CUE_R3_STARTUP: "res://assets/audio/narrative/r3_startup.wav",
	CUE_C4_SINGLE_LINE: "res://assets/audio/narrative/c4_single_line.wav",
	CUE_SPLITTER_BENCH_LATCH: "res://assets/audio/narrative/splitter_bench_latch.wav",
	CUE_C4_DUAL_LINE_TEST: "res://assets/audio/narrative/c4_dual_line_test.wav",
	CUE_C4_DUAL_LINE_STORM: "res://assets/audio/narrative/c4_dual_line_storm.wav",
	CUE_FRONT_PRESSURE: "res://assets/audio/narrative/front_pressure.wav",
}

static var _stream_cache: Dictionary = {}


static func stream_for(cue_id: String) -> AudioStream:
	var normalized_id := cue_id.strip_edges()
	if normalized_id.is_empty():
		return null
	if _stream_cache.has(normalized_id):
		return _stream_cache[normalized_id] as AudioStream
	var stream_path := str(_STREAM_PATHS.get(normalized_id, ""))
	if stream_path.is_empty() or not ResourceLoader.exists(stream_path, "AudioStream"):
		return null
	var stream := ResourceLoader.load(stream_path, "AudioStream") as AudioStream
	if stream != null:
		_stream_cache[normalized_id] = stream
	return stream


static func has_cue(cue_id: String) -> bool:
	return stream_for(cue_id) != null


static func cue_ids() -> Array[String]:
	var result: Array[String] = []
	for cue_id in _STREAM_PATHS.keys():
		result.append(str(cue_id))
	result.sort()
	return result
