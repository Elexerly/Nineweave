extends RefCounted
## Release builds never opt into the dedicated, separately saved staging environment.
const STAGING_FEATURE := "lexerly_test"
const LIVE_ORIGIN := "https://nineweave.grok.me"
const STAGING_ORIGIN := "https://br-still-mode-bdsyavce-lexerlytest.compute.c-8.us-east-2.aws.neon.tech"
const LIVE_DATA := "user://"
const STAGING_DATA := "user://lexerly-staging-"
static func staging() -> bool:
	return OS.has_feature(STAGING_FEATURE)
static func origin() -> String:
	return STAGING_ORIGIN if staging() else LIVE_ORIGIN
static func save_path(filename: String) -> String:
	return (STAGING_DATA if staging() else LIVE_DATA)+filename
static func pinned_base(requested: String) -> String:
	# A configured staging client must not read or submit to the live API,
	# even if an individual caller supplies the legacy/default production URL.
	if staging(): return STAGING_ORIGIN
	return requested if requested.begins_with("https://") or requested.begins_with("http://") else LIVE_ORIGIN
