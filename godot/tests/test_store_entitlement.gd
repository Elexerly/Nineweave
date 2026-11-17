extends SceneTree
const Provider = preload("res://native/store_entitlement.gd")
var checks := 0
class FakeStore extends RefCounted:
	var ack := []
	func acknowledge(token: String): ack.append(token)
func check(ok: bool, label: String):
	checks += 1
	if not ok: push_error(label); quit(1)
func _initialize():
	var p = Provider.new()
	var fake = FakeStore.new()
	p._store = fake
	p._product_id = "test.remove_ads"
	check(not p.entitlement_ready() and not p.ads_removed(), "unknown cannot unlock")
	p._handle_event({"kind":"entitlement","product_id":"test.remove_ads","owned":true})
	check(not p.ads_removed(), "missing verification rejected")
	p._handle_event({"kind":"entitlement","product_id":"other","owned":true,"verified":true})
	check(not p.ads_removed(), "wrong product rejected")
	p._handle_event({"kind":"purchase","state":"pending"})
	check(not p.ads_removed(), "pending cannot unlock")
	p._handle_event({"kind":"purchase","state":"cancelled"})
	check(not p.ads_removed(), "cancel cannot unlock")
	p.entitlement_changed.connect(func(): check(fake.ack.is_empty(), "delivery before finish"), CONNECT_ONE_SHOT)
	p._handle_event({"kind":"entitlement","product_id":"test.remove_ads","owned":true,"verified":true,"delivery_token":"one"})
	check(p.ads_removed() and p.entitlement_ready(), "verified grants")
	check(fake.ack == ["one"], "delivery acknowledged")
	p._handle_event({"kind":"error","operation":"product","message":"offline"})
	check(p.ads_removed(), "price lookup failure preserves verified entitlement")
	p._handle_event({"kind":"entitlement","product_id":"test.remove_ads","owned":false,"verified":true})
	check(p.entitlement_ready() and not p.ads_removed(), "revocation removes")
	p._handle_event({"kind":"error","operation":"verification","message":"invalid"})
	check(not p.entitlement_ready(), "verification error is unknown, not forced ads")
	var statuses: Array[String] = []
	p.status_changed.connect(func(state: String): statuses.append(state))
	p._handle_event({"kind":"restore","state":"unconfirmed"})
	check(statuses == ["unconfirmed"] and not p.entitlement_ready(), "unconfirmed restore never reports success or grants")
	var native = FileAccess.get_file_as_string("res://native/storekit2/NineweaveStoreKit.swift")
	check(native.contains("if await self.refreshEntitlement() {"), "source guard: restore requires confirmed refresh")
	check(native.contains("refreshSequence == sequence"), "source guard: stale snapshots discarded")
	check(native.contains("revision == startingRevision"), "source guard: purchase update supersedes snapshot")
	p.free()
	print("Store entitlement: %d checks passed" % checks)
	quit()
