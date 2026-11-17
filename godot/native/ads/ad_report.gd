extends RefCounted
## Session-only local report draft. No networking, identity, file persistence or auto-send.
const REASONS = ["Inappropriate content", "Not appropriate for the game's age rating", "Misleading ad", "Cannot close the ad"]
var _last: Dictionary = {}
func capture(response: Dictionary, placement: String):
	# Called only from SDK showed callback, not load/show-attempt or synthetic impression.
	_last = {"response_id": str(response.get("response_id", "")).strip_edges().left(256),
		"placement": placement.left(64), "time_utc": Time.get_datetime_string_from_system(true)+"Z"}
func available() -> bool: return not _last.is_empty()
func draft(reason: String, details: String = "") -> String:
	if not available(): return "No ad presentation has been recorded in this session."
	if reason not in REASONS: return "Choose a report reason."
	return "Nineweave ad report (not sent)\nReason: %s\nTime UTC: %s\nPlacement: %s\nAd response ID: %s\nDetails: %s" % [reason,_last.time_utc,_last.placement,_last.response_id if not _last.response_id.is_empty() else "Unavailable",details.strip_edges().left(1000)]
