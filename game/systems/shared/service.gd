class_name Service
## Lazy installation for this stream's service nodes (Ownership, Bounty, Stealth,
## EconomyService, NpcRegistry, PropertyRegistry, Jobs). A world scene may add them
## explicitly; where it has not, the first caller installs one under the scene tree root, so
## no new autoload is needed and the systems work in tests, in the smoke run and in a world
## scene alike. Names are fixed so a second call finds the first node.

## Nodes created but not yet in the tree (the deferred path), so a second `ensure()` in the
## same frame finds the first one instead of building a rival.
static var _pending: Dictionary = {}


static func ensure(script: Script, node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var existing := tree.root.get_node_or_null(NodePath(node_name))
	if existing != null and is_instance_valid(existing):
		_pending.erase(node_name)
		return existing
	var waiting: Variant = _pending.get(node_name)
	if waiting is Node and is_instance_valid(waiting):
		return waiting
	var n: Node = script.new()
	n.name = node_name
	if tree.root.is_node_ready():
		tree.root.add_child(n)
	else:
		_pending[node_name] = n
		tree.root.add_child.call_deferred(n)
	return n


## The node of a group, if one is in the tree.
static func in_group(group: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group(group)
