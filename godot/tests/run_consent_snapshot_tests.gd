extends SceneTree
const Guard = preload("res://native/ump/ad_consent_guard.gd")
const Snapshot = preload("res://native/ump/consent_snapshot.gd")
class Bridge extends Node:
	var requests = []
	var events = []
	func request_snapshot(nonce): requests.append(nonce)
	func pop_snapshot(): return events.pop_front() if not events.is_empty() else ""
	func reply(nonce, value, privacy = "required"):
		events.append(JSON.stringify({"nonce":nonce,"can_request_ads":value,"privacy_options_status":privacy}))
var checks = 0
var failures = 0
func ok(value, label):
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _initialize(): run.call_deferred()
func run():
	var consent = Snapshot.new(); var bridge = Bridge.new(); root.add_child(consent); root.add_child(bridge)
	consent.set_process(false)
	var clock = [100.0]; consent.time_source = func(): return clock[0]
	ok(not consent.allowed() and consent.privacy_options_status() == "unknown","unknown is closed")
	ok(not consent.attach_bridge(null) and not consent.refresh(),"absent native plugin closed")
	ok(consent.attach_bridge(bridge) and bridge.requests.is_empty(),"attach never requests consent or ads")
	ok(consent.refresh() and not consent.refresh() and bridge.requests.size() == 1,"only one pending native read")
	ok(not consent.allowed(),"pending denies")
	var first = bridge.requests[-1]
	bridge.reply("wrong",true); consent._process(0)
	ok(not consent.allowed(),"wrong nonce denied")
	bridge.reply(first,true); consent._process(0)
	ok(consent.allowed() and consent.privacy_options_status() == "required","fresh authoritative bool accepted")
	consent.invalidate(); bridge.reply(first,true); consent._process(0)
	ok(not consent.allowed(),"privacy invalidation rejects late old grant")
	consent.refresh(); bridge.reply(bridge.requests[-1],"true"); consent._process(0)
	ok(not consent.allowed(),"string true never grants permission")
	consent.refresh(); bridge.reply(bridge.requests[-1],true); clock[0] += 6; consent._process(0)
	ok(not consent.allowed(),"slow queued snapshot expired from request time")
	consent.refresh(); bridge.reply(bridge.requests[-1],true,"not_required"); consent._process(0)
	ok(consent.allowed(),"fresh later grant works")
	clock[0] += 6
	ok(not consent.allowed() and consent.privacy_options_status() == "unknown","cached grant expires even before next process")
	consent._process(0); consent.refresh(); bridge.reply(bridge.requests[-1],true); consent._process(0)
	consent.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	ok(not consent.allowed(),"background invalidates grant")
	consent.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	ok(not consent.allowed(),"resume does not fabricate permission")
	consent.refresh(); var old_nonce = bridge.requests[-1]; consent.attach_bridge(bridge); bridge.reply(old_nonce,true); consent._process(0)
	ok(not consent.allowed(),"provider replacement rejects stale response")
	consent.refresh(); bridge.events.append("bad-json"); consent._process(0)
	ok(not consent.allowed(),"malformed native message closed")
	bridge.reply(bridge.requests[-1],false); consent._process(0)
	ok(not consent.allowed(),"authoritative denial respected")
	var guard = Guard.new(); root.add_child(guard); guard.setup(consent,func(): return true)
	var decisions = []; var receive = func(value): decisions.append(value)
	guard.request_load(receive); var load_nonce = bridge.requests[-1]; bridge.reply(load_nonce,true); consent._process(0)
	ok(decisions == [true],"guard load requires fresh native read")
	guard.request_show(receive)
	ok(bridge.requests[-1] != load_nonce and decisions == [true],"show cannot reuse cached load grant")
	guard.before_privacy_form(); bridge.reply(bridge.requests[-1],true); consent._process(0)
	ok(decisions == [true,false],"privacy form invalidates pending ad before presentation")
	guard.request_show(receive); ok(decisions[-1] == false,"no ad while privacy form open")
	guard.after_privacy_form(); clock[0] += 20
	ok(guard.privacy_options_reachable(),"privacy entry stays reachable with expired unknown status")
	guard.request_show(receive); bridge.reply(bridge.requests[-1],true); consent._process(0)
	ok(decisions[-1] == true,"after privacy closure next request independently refreshes")
	guard.request_load(receive); guard.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	ok(decisions[-1] == false,"background cancels pending operation")
	guard.free()
	consent.free(); bridge.free()
	print("NINEWEAVE_CONSENT_SNAPSHOT ","PASS" if failures == 0 else "FAIL"," checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
