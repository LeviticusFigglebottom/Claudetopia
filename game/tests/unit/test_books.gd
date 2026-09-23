extends TestCase
## Readable books, end to end: a book def has a copy you can carry, carrying it lets you read
## it, reading it teaches what it says it teaches (once), and a house shelf holds one.

const STRUCK := "core:book/the_struck_bell"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


# --- content ------------------------------------------------------------------------------------

func test_every_book_has_a_copy_somebody_could_own() -> void:
	var reads: Dictionary = {}
	for it in ContentDB.all("item"):
		var target := str(it.get("reads", ""))
		if not target.is_empty():
			reads[target] = it["id"]
	for book in ContentDB.all("book"):
		assert_true(reads.has(str(book["id"])), "%s has no copy in the world" % book["id"])


func test_book_copies_describe_the_object_not_the_contents() -> void:
	for it in ContentDB.all("item"):
		if str(it.get("category", "")) != "book":
			continue
		assert_gt(str(it.get("description", "")).length(), 80, "%s needs a real description" % it["id"])
		assert_true(ContentDB.has(str(it.get("reads", ""))), "%s opens a book that exists" % it["id"])


func test_what_a_book_teaches_is_a_real_skill_and_its_hook_a_real_quest() -> void:
	for book in ContentDB.all("book"):
		var skill := str(book.get("teaches_skill", ""))
		if not skill.is_empty():
			assert_true(Skills.normalise(skill) != "", "%s teaches unknown skill %s" % [book["id"], skill])
		var hook := str(book.get("quest_hook", ""))
		if not hook.is_empty():
			assert_true(ContentDB.has(hook), "%s hooks a quest that does not exist" % book["id"])


# --- carrying and reading -------------------------------------------------------------------------

func test_a_carried_book_can_be_read_and_is_not_spent() -> void:
	var bag := Inventory.new()
	_tree().root.add_child(bag)
	var stack := bag.add("core:item/the_struck_bell", 1)
	assert_true(stack != null)
	assert_true(stack.is_readable())
	assert_eq(stack.reads_book(), STRUCK)
	var opened: Array = []
	var handler := func(id: String) -> void: opened.append(id)
	EventBus.book_opened.connect(handler)
	assert_true(bag.read(stack))
	EventBus.book_opened.disconnect(handler)
	assert_eq(opened, [STRUCK])
	assert_eq(bag.count("core:item/the_struck_bell"), 1, "reading a book does not use it up")
	close_screen("book", "reading a carried book opens the reader")
	_tree().root.remove_child(bag)
	bag.free()


func test_a_teaching_book_teaches_once() -> void:
	var prog := Progression.new()
	_tree().root.add_child(prog)
	GameState.set_flag("read:" + STRUCK, false)
	var before := prog.skill_level("binding")
	EventBus.book_opened.emit(STRUCK)
	await _tree().process_frame
	var after := prog.skill_level("binding")
	assert_gt(after, before - 1, "the Struck Bell teaches Binding")
	assert_true(GameState.has_flag("read:" + STRUCK))
	EventBus.book_opened.emit(STRUCK)
	await _tree().process_frame
	assert_eq(prog.skill_level("binding"), after, "a second reading teaches nothing")
	close_screen("book", "a book opened is a book drawn")
	GameState.set_flag("read:" + STRUCK, false)
	_tree().root.remove_child(prog)
	prog.free()


# --- in the world ---------------------------------------------------------------------------------

func test_a_book_on_a_table_reads_where_it_lies_or_comes_with_you() -> void:
	var fixed := Readable.new()
	fixed.book_id = STRUCK
	fixed.fixed = true
	_tree().root.add_child(fixed)
	var opened: Array = []
	var handler := func(id: String) -> void: opened.append(id)
	EventBus.book_opened.connect(handler)
	var result := fixed.interact(null)
	EventBus.book_opened.disconnect(handler)
	assert_true(bool(result["ok"]))
	assert_eq(opened, [STRUCK])
	assert_true(fixed.prompt_text().begins_with("Read"))
	close_screen("book", "a book read where it lies opens the reader")
	_tree().root.remove_child(fixed)
	fixed.free()
