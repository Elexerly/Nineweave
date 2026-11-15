extends SceneTree
## CPU geometry proof only; not a screenshot or shader/renderer validation.
const Rig = preload("res://characters/rig.gd")
const Roster = preload("res://characters/roster.gd")
var triangles: Array = []
var faces = false
func _initialize(): run.call_deferred()
func walk(node: Node2D):
	if not node.visible: return
	for child in node.get_children():
		if child is Node2D and child.show_behind_parent: walk(child)
	if node is Rig.Cutout and node.mesh != null:
		var arrays = node.mesh.surface_get_arrays(0)
		var vertices = arrays[Mesh.ARRAY_VERTEX]; var colors = arrays[Mesh.ARRAY_COLOR]
		for i in range(0,vertices.size(),3):
			var coords = []
			for j in range(3):
				var v = vertices[i+j]; var p = node.get_global_transform()*Vector2(v.x,v.y)
				coords.append(p.x); coords.append(p.y)
			triangles.append([coords,colors[i].to_html(false)])
	for child in node.get_children():
		if child is Node2D and not child.show_behind_parent: walk(child)
func run():
	faces = "--faces" in OS.get_cmdline_user_args()
	for i in range(28 if faces else 12):
		var rig = Rig.new(); rig.hero_id = Roster.DATA[[0,1,4,10][i/7] if faces else i].id; rig.frozen = true
		rig.position = Vector2(i%7*180,int(i/7)*210) if faces else Vector2(i%4*310,int(i/4)*540)
		rig.size = Vector2(180,200) if faces else Vector2(310,520); rig.bust = faces; root.add_child(rig)
		rig.clip_age = 2; rig.pose(1.4)
		if faces: rig._set_expression(Rig.Reactions.EXPRESSIONS[i%7])
		walk(rig.actor)
	var file = FileAccess.open("res://.godot/rig-proof.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(triangles)); file.close()
	print("RIG PROOF triangles=",triangles.size()); quit()
