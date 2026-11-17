extends Node2D

const COLS := 15
const ROWS := 13
const CELL := 44
const ORIGIN := Vector2(30, 150)
const SAVE_PATH := "user://savegame.json"

# Cevherler: ad, renk, çıkış katı, çıkma ağırlığı, can çarpanı, para değeri
const ORES := [
	{"name": "coal", "color": Color("2b2b2b"), "min_floor": 1, "weight": 20, "hp": 1.0, "value": 2},
	{"name": "copper", "color": Color("c8743a"), "min_floor": 1, "weight": 14, "hp": 1.3, "value": 5},
	{"name": "iron", "color": Color("b9bcc4"), "min_floor": 10, "weight": 10, "hp": 1.8, "value": 12},
	{"name": "gold", "color": Color("f2c230"), "min_floor": 12, "weight": 7, "hp": 2.5, "value": 40},
]
const STONE_WEIGHT := 50
const STONE_COLOR := Color("6b6b72")
const STONE_VALUE := 1

# Plate tarifleri: gereken cevher adedi ve üretim süresi (sn). Her üretim 1 coal yakar.
const RECIPES := {
	"copper": {"ore": 10, "time": 15.0},
	"iron": {"ore": 20, "time": 25.0},
	"gold": {"ore": 40, "time": 40.0},
}
const FURNACE_UNLOCK_FLOORS := [5, 15, 50, 100, 250, 500]
const FIRST_DWARF_COST := 100
const PRESTIGE_FLOOR := 50
const PRESTIGE_BASE_REWARD := 5
const PRESTIGE_REWARD_INTERVAL := 10
const PRESTIGE_INTERVAL_BONUS := 5
const PRESTIGE_UPGRADES := [
	{"id": "damage", "title": "Kalıcı kazma hasarı", "cost": 1, "max": 100},
	{"id": "income", "title": "Kalıcı maden geliri", "cost": 1, "max": 25},
	{"id": "starting_money", "title": "Başlangıç parası", "cost": 2, "max": 50},
]

# Cüce türleri: temel hasar, satın alma maliyeti (kendi plate'inden), çerçeve rengi
const DWARF_TYPES := {
	"copper": {"title": "Copper Axe", "dmg": 1.0, "cost": 10, "color": Color("ff9a4d")},
	"iron": {"title": "Iron Axe", "dmg": 4.0, "cost": 10, "color": Color("dfe6ff")},
	"gold": {"title": "Gold Axe", "dmg": 12.0, "cost": 10, "color": Color("ffe14d")},
}
const DWARF_TIME := 1.0

# Para ile alınan geliştirmeler
const UPGRADES := [
	{"id": "tap", "title": "Dokunma hasarı", "cost": 10, "max": 9999},
	{"id": "crit_chance", "title": "Kritik şansı", "cost": 25, "max": 25},
	{"id": "crit_dmg", "title": "Kritik hasar", "cost": 30, "max": 9999},
	{"id": "dwarf", "title": "Cüce hasarı", "cost": 40, "max": 9999},
]

const TAB_NAMES := ["Fırın", "Market", "Cüceler", "Geliştir", "Prestij"]

var floor_no := 1
var blocks: Array = []
var alive: Array[int] = []
var tap_target := -1
var money := 0.0
var ores := {"coal": 0, "copper": 0, "iron": 0, "gold": 0}
var plates := {"copper": 0, "iron": 0, "gold": 0}
var furnaces: Array = []
var dwarves: Array = [null, null, null]
var first_dwarf_purchased := false
var upgrade_levels := {"tap": 0, "crit_chance": 0, "crit_dmg": 0, "dwarf": 0}
var prestige_points := 0
var prestige_count := 0
var prestige_upgrades := {"damage": 0, "income": 0, "starting_money": 0}
var tab := 0
var buttons: Array = []
var autosave_timer := 0.0


func _ready() -> void:
	randomize()
	for unlock_floor in FURNACE_UNLOCK_FLOORS:
		furnaces.append({"unlock": unlock_floor, "selected": "copper", "active": "", "time": 0.0})
	if not load_game():
		new_floor()


func _process(delta: float) -> void:
	update_furnace(delta)
	for d in dwarves:
		if d != null:
			d["t"] += delta
			if d["t"] >= DWARF_TIME:
				d["t"] = 0.0
				d["target"] = hit(d["target"], dwarf_damage(d))
	autosave_timer += delta
	if autosave_timer >= 5.0:
		autosave_timer = 0.0
		save_game()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()


func save_game() -> void:
	var saved_blocks: Array = []
	for block in blocks:
		var ore_name: String = "" if block["ore"].is_empty() else block["ore"]["name"]
		saved_blocks.append({"ore": ore_name, "hp": block["hp"], "max_hp": block["max_hp"], "seed": block["seed"]})
	var save_data := {
		"version": 1,
		"floor_no": floor_no,
		"money": money,
		"ores": ores,
		"plates": plates,
		"furnaces": furnaces,
		"dwarves": dwarves,
		"first_dwarf_purchased": first_dwarf_purchased,
		"upgrade_levels": upgrade_levels,
		"prestige_points": prestige_points,
		"prestige_count": prestige_count,
		"prestige_upgrades": prestige_upgrades,
		"tab": tab,
		"tap_target": tap_target,
		"blocks": saved_blocks,
		"alive": alive,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(save_data))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false
	var save_data: Dictionary = parsed
	var saved_blocks: Variant = save_data.get("blocks", [])
	if not saved_blocks is Array or saved_blocks.size() != COLS * ROWS:
		return false

	floor_no = maxi(1, int(save_data.get("floor_no", 1)))
	money = maxf(0.0, float(save_data.get("money", 0.0)))
	var saved_ores: Dictionary = save_data.get("ores", {})
	for key in ores:
		ores[key] = maxi(0, int(saved_ores.get(key, 0)))
	var saved_plates: Dictionary = save_data.get("plates", {})
	for key in plates:
		plates[key] = maxi(0, int(saved_plates.get(key, 0)))
	var saved_upgrades: Dictionary = save_data.get("upgrade_levels", {})
	for key in upgrade_levels:
		upgrade_levels[key] = maxi(0, int(saved_upgrades.get(key, 0)))
	prestige_points = maxi(0, int(save_data.get("prestige_points", 0)))
	prestige_count = maxi(0, int(save_data.get("prestige_count", 0)))
	var saved_prestige_upgrades: Dictionary = save_data.get("prestige_upgrades", {})
	for key in prestige_upgrades:
		prestige_upgrades[key] = maxi(0, int(saved_prestige_upgrades.get(key, 0)))
	first_dwarf_purchased = bool(save_data.get("first_dwarf_purchased", false))
	tab = clampi(int(save_data.get("tab", 0)), 0, TAB_NAMES.size() - 1)

	blocks.clear()
	for saved_block in saved_blocks:
		var ore: Dictionary = {}
		var ore_name := str(saved_block.get("ore", ""))
		for definition in ORES:
			if definition["name"] == ore_name:
				ore = definition
				break
		var max_hp := maxf(1.0, float(saved_block.get("max_hp", 1.0)))
		blocks.append({
			"ore": ore,
			"hp": clampf(float(saved_block.get("hp", max_hp)), 0.0, max_hp),
			"max_hp": max_hp,
			"seed": int(saved_block.get("seed", 0)),
		})

	alive.clear()
	for saved_index in save_data.get("alive", []):
		var block_index := int(saved_index)
		if block_index >= 0 and block_index < blocks.size():
			alive.append(block_index)
	tap_target = int(save_data.get("tap_target", -1))
	if not alive.has(tap_target):
		tap_target = -1

	var saved_furnaces: Array = save_data.get("furnaces", [])
	for i in mini(furnaces.size(), saved_furnaces.size()):
		var saved_furnace: Dictionary = saved_furnaces[i]
		var selected := str(saved_furnace.get("selected", "copper"))
		var active := str(saved_furnace.get("active", ""))
		if not RECIPES.has(selected):
			selected = "copper"
		if not RECIPES.has(active):
			active = ""
		furnaces[i]["selected"] = selected
		furnaces[i]["active"] = active
		furnaces[i]["time"] = maxf(0.0, float(saved_furnace.get("time", 0.0)))

	var saved_dwarves: Array = save_data.get("dwarves", [])
	for i in dwarves.size():
		if i >= saved_dwarves.size() or not saved_dwarves[i] is Dictionary:
			continue
		var saved_dwarf: Dictionary = saved_dwarves[i]
		var dwarf_type := str(saved_dwarf.get("type", ""))
		if DWARF_TYPES.has(dwarf_type):
			var dwarf_target := int(saved_dwarf.get("target", -1))
			if not alive.has(dwarf_target):
				dwarf_target = -1
			dwarves[i] = {
				"type": dwarf_type,
				"level": maxi(1, int(saved_dwarf.get("level", 1))),
				"target": dwarf_target,
				"t": maxf(0.0, float(saved_dwarf.get("t", 0.0))),
			}
	if alive.is_empty() and floor_no >= PRESTIGE_FLOOR:
		floor_no += 1
		new_floor()
	return true


# --- Kat ve bloklar ---

func new_floor() -> void:
	blocks.clear()
	alive.clear()
	tap_target = -1
	for d in dwarves:
		if d != null:
			d["target"] = -1
	var base_hp := ceilf(3.0 * pow(1.12, floor_no - 1))
	for i in COLS * ROWS:
		var ore := pick_ore()
		var mult: float = ore["hp"] if not ore.is_empty() else 1.0
		var hp := ceilf(base_hp * mult)
		blocks.append({"ore": ore, "hp": hp, "max_hp": hp, "seed": randi()})
		alive.append(i)


func pick_ore() -> Dictionary:
	var pool: Array = []
	var total := STONE_WEIGHT
	for o in ORES:
		if floor_no >= o["min_floor"]:
			pool.append(o)
			total += o["weight"]
	var roll := randi() % total
	for o in pool:
		roll -= o["weight"]
		if roll < 0:
			return o
	return {}


# Her sütunda altındaki blok kırılmışsa erişilebilir kabul edilir
func exposed_targets() -> Array[int]:
	var exposed: Array[int] = []
	for i in alive:
		var row: int = i / COLS
		var column: int = i % COLS
		var blocked := false
		for other in alive:
			if other % COLS == column and other / COLS > row:
				blocked = true
				break
		if not blocked:
			exposed.append(i)
	return exposed


func pick_target() -> int:
	var taken: Array = [tap_target]
	for d in dwarves:
		if d != null:
			taken.append(d["target"])
	var exposed := exposed_targets()
	var free: Array[int] = []
	for i in exposed:
		if not taken.has(i):
			free.append(i)
	var pool: Array[int] = free if not free.is_empty() else exposed
	if pool.is_empty():
		return -1
	return pool[randi() % pool.size()]


# Vuran tarafın hedefini alır, vuruştan sonraki hedefi döndürür (-1: yeni seçilecek)
func hit(idx: int, base_dmg: float) -> int:
	if idx == -1 or not alive.has(idx):
		idx = pick_target()
	if idx == -1:
		return -1
	var dmg := base_dmg
	if randf() < crit_chance():
		dmg *= crit_mult()
	var b: Dictionary = blocks[idx]
	b["hp"] -= dmg
	if b["hp"] <= 0:
		break_block(idx)
		return -1
	return idx


func break_block(idx: int) -> void:
	var b: Dictionary = blocks[idx]
	var value := STONE_VALUE
	if not b["ore"].is_empty():
		ores[b["ore"]["name"]] += 1
		value = b["ore"]["value"]
	money += value * (1.0 + 0.15 * (floor_no - 1)) * (1.0 + 0.1 * prestige_upgrades["income"])
	alive.erase(idx)
	if tap_target == idx:
		tap_target = -1
	for d in dwarves:
		if d != null and d["target"] == idx:
			d["target"] = -1
	if alive.is_empty():
		floor_no += 1
		new_floor()


# --- Fırın ---

func update_furnace(delta: float) -> void:
	for furnace in furnaces:
		if floor_no < furnace["unlock"]:
			continue
		if furnace["active"] == "":
			var recipe: String = furnace["selected"]
			var requirements: Dictionary = RECIPES[recipe]
			if ores[recipe] >= requirements["ore"] and ores["coal"] >= 1:
				ores[recipe] -= requirements["ore"]
				ores["coal"] -= 1
				furnace["active"] = recipe
				furnace["time"] = 0.0
		else:
			var active_recipe: String = furnace["active"]
			furnace["time"] += delta
			if furnace["time"] >= RECIPES[active_recipe]["time"]:
				plates[active_recipe] += 1
				furnace["active"] = ""
				furnace["time"] = 0.0


func select_furnace_recipe(index: int, recipe: String) -> void:
	if index >= 0 and index < furnaces.size() and recipe_unlocked(recipe):
		furnaces[index]["selected"] = recipe


func recipe_unlocked(recipe: String) -> bool:
	for ore in ORES:
		if ore["name"] == recipe:
			return floor_no >= ore["min_floor"]
	return false


# --- Hasar hesapları ---

func tap_damage() -> float:
	return 1.0 + upgrade_levels["tap"] + prestige_upgrades["damage"]


func crit_chance() -> float:
	return 0.02 * upgrade_levels["crit_chance"]


func crit_mult() -> float:
	return 1.5 + 0.25 * upgrade_levels["crit_dmg"]


func dwarf_damage(d: Dictionary) -> float:
	var base: float = DWARF_TYPES[d["type"]]["dmg"]
	return base * (1.0 + 0.5 * (d["level"] - 1)) * (1.0 + 0.1 * upgrade_levels["dwarf"])


func dwarf_upgrade_cost(d: Dictionary) -> int:
	return int(ceilf(5.0 * pow(1.6, d["level"] - 1)))


func upgrade_cost(u: Dictionary) -> int:
	return int(ceilf(u["cost"] * pow(1.6, upgrade_levels[u["id"]])))


func free_slot() -> int:
	return dwarves.find(null)


# --- Satın alma ---

func buy_dwarf(type: String) -> void:
	var slot := free_slot()
	var info: Dictionary = DWARF_TYPES[type]
	var uses_money := type == "copper" and not first_dwarf_purchased
	var cost: int = FIRST_DWARF_COST if uses_money else info["cost"]
	var can_afford: bool = money >= cost if uses_money else plates[type] >= cost
	if slot != -1 and can_afford:
		if uses_money:
			money -= cost
		else:
			plates[type] -= cost
		dwarves[slot] = {"type": type, "level": 1, "target": -1, "t": 0.0}
		first_dwarf_purchased = true


func upgrade_dwarf(slot: int) -> void:
	var d: Dictionary = dwarves[slot]
	var cost := dwarf_upgrade_cost(d)
	if plates[d["type"]] >= cost:
		plates[d["type"]] -= cost
		d["level"] += 1


func buy_upgrade(id: String) -> void:
	for u in UPGRADES:
		if u["id"] == id:
			var cost := upgrade_cost(u)
			if money >= cost and upgrade_levels[id] < u["max"]:
				money -= cost
				upgrade_levels[id] += 1


func prestige_upgrade_cost(upgrade: Dictionary) -> int:
	return int(upgrade["cost"]) * (prestige_upgrades[upgrade["id"]] + 1)


func buy_prestige_upgrade(id: String) -> void:
	for upgrade in PRESTIGE_UPGRADES:
		if upgrade["id"] == id and prestige_upgrades[id] < upgrade["max"]:
			var cost := prestige_upgrade_cost(upgrade)
			if prestige_points >= cost:
				prestige_points -= cost
				prestige_upgrades[id] += 1
				save_game()


func prestige_reward() -> int:
	if floor_no < PRESTIGE_FLOOR:
		return 0
	var floors_beyond_unlock := floor_no - PRESTIGE_FLOOR
	var interval_bonus := int(floors_beyond_unlock / PRESTIGE_REWARD_INTERVAL) * PRESTIGE_INTERVAL_BONUS
	return PRESTIGE_BASE_REWARD + floors_beyond_unlock + interval_bonus


func perform_prestige() -> void:
	if floor_no < PRESTIGE_FLOOR:
		return
	prestige_points += prestige_reward()
	prestige_count += 1
	floor_no = 1
	money = prestige_upgrades["starting_money"] * 100
	for key in ores:
		ores[key] = 0
	for key in plates:
		plates[key] = 0
	for key in upgrade_levels:
		upgrade_levels[key] = 0
	for i in dwarves.size():
		dwarves[i] = null
	first_dwarf_purchased = false
	for furnace in furnaces:
		furnace["selected"] = "copper"
		furnace["active"] = ""
		furnace["time"] = 0.0
	tap_target = -1
	tab = 4
	new_floor()
	save_game()


func set_tab(i: int) -> void:
	tab = i


# --- Giriş ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for b in buttons:
			if b["rect"].has_point(event.position):
				if b["enabled"]:
					b["cb"].call()
				return
		var column := int((event.position.x - ORIGIN.x) / CELL)
		var row := int((event.position.y - ORIGIN.y) / CELL)
		if column >= 0 and column < COLS and row >= 0 and row < ROWS:
			var selected := row * COLS + column
			if exposed_targets().has(selected):
				tap_target = hit(selected, tap_damage())


# --- Çizim ---

func fmt(n: float) -> String:
	if n >= 1e9:
		return "%.2fB" % (n / 1e9)
	if n >= 1e6:
		return "%.2fM" % (n / 1e6)
	if n >= 1e4:
		return "%.1fK" % (n / 1e3)
	return str(int(n))


func text(pos: Vector2, s: String, size: int, col: Color = Color.WHITE) -> void:
	draw_string(ThemeDB.fallback_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func draw_button(rect: Rect2, label: String, enabled: bool, cb: Callable, selected: bool = false) -> void:
	var fill := Color("4c8f55") if enabled and selected else Color("2f6f3a") if enabled else Color("3a3a42")
	draw_rect(rect, fill)
	draw_rect(rect, Color("b6edbf") if selected else Color("8fd19e") if enabled else Color("55555e"), false, 2.0)
	var pos := Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + 8)
	draw_string(ThemeDB.fallback_font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, Color.WHITE if enabled else Color("999999"))
	buttons.append({"rect": rect, "enabled": enabled, "cb": cb})


func _draw() -> void:
	buttons.clear()
	draw_mine_backdrop()
	text(Vector2(30, 60), "KAT %d" % floor_no, 40)
	text(Vector2(30, 112), "Kalan blok: %d" % alive.size(), 24, Color("aaaaaa"))
	text(Vector2(400, 60), "Para: %s" % fmt(money), 34, Color("f2c230"))

	draw_grid()
	draw_inventory()

	for i in TAB_NAMES.size():
		var r := Rect2(30 + i * 136, 830, 126, 56)
		draw_rect(r, Color("46465a") if tab == i else Color("2a2a36"))
		draw_string(ThemeDB.fallback_font, Vector2(r.position.x, r.position.y + 37), TAB_NAMES[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 24, Color.WHITE)
		buttons.append({"rect": r, "enabled": true, "cb": set_tab.bind(i)})

	match tab:
		0: draw_furnace_panel()
		1: draw_market_panel()
		2: draw_dwarf_panel()
		3: draw_upgrade_panel()
		4: draw_prestige_panel()


func draw_mine_backdrop() -> void:
	draw_rect(Rect2(0, 0, 720, 1280), Color("17171d"))
	draw_rect(Rect2(18, 138, 684, 590), Color("101116"))
	draw_rect(Rect2(22, 142, 676, 582), Color("393841"))
	draw_rect(Rect2(26, 146, 668, 574), Color("25252d"))
	draw_rect(Rect2(0, 0, 720, 130), Color("3b2418"))
	for row in 5:
		var y := row * 25
		var plank_color := Color("513222") if row % 2 == 0 else Color("462a1d")
		draw_rect(Rect2(0, y, 720, 23), plank_color)
		draw_rect(Rect2(0, y + 22, 720, 3), Color("2a1b16"))
		for mark in 8:
			var x := (mark * 97 + row * 31) % 710
			draw_rect(Rect2(x, y + 5 + (mark % 3) * 5, 18 + mark % 13, 2), Color("68432b"))
		if row % 2 == 0:
			for nail in 8:
				draw_rect(Rect2(nail * 96 + 12, y + 10, 3, 3), Color("93643b"))


func draw_grid() -> void:
	for i in alive:
		var b: Dictionary = blocks[i]
		var pos := ORIGIN + Vector2((i % COLS) * CELL, (i / COLS) * CELL)
		var seed: int = b["seed"]
		var shade := float(seed & 7) / 100.0
		var stone_color := STONE_COLOR.lightened(shade)
		draw_rect(Rect2(pos, Vector2(CELL, CELL)), Color("17171d"))
		draw_rect(Rect2(pos + Vector2(2, 2), Vector2(CELL - 4, CELL - 4)), stone_color.darkened(0.18))
		draw_rect(Rect2(pos + Vector2(4, 4), Vector2(CELL - 8, CELL - 8)), stone_color)
		for speckle in 4:
			var bits := (seed >> (speckle * 6)) & 255
			var px := 5 + (bits % 8) * 4
			var py := 5 + ((bits / 8) % 8) * 4
			draw_rect(Rect2(pos + Vector2(px, py), Vector2(3, 3)), stone_color.lightened(0.12))
		if not b["ore"].is_empty():
			draw_ore_art(pos, b["ore"]["name"], b["ore"]["color"])
		var dmg_ratio: float = 1.0 - b["hp"] / b["max_hp"]
		if dmg_ratio > 0.0:
			draw_rect(Rect2(pos, Vector2(CELL, CELL)), Color(0, 0, 0, dmg_ratio * 0.35))
			if dmg_ratio > 0.2:
				draw_line(pos + Vector2(14, 7), pos + Vector2(20, 18), Color("19171a"), 2.0)
			if dmg_ratio > 0.45:
				draw_line(pos + Vector2(20, 18), pos + Vector2(14, 27), Color("19171a"), 2.0)
				draw_line(pos + Vector2(20, 18), pos + Vector2(31, 25), Color("19171a"), 2.0)
		if i == tap_target:
			draw_rect(Rect2(pos + Vector2(1, 1), Vector2(CELL - 2, CELL - 2)), Color("ffe17a"), false, 3.0)
		if i == tap_target:
			draw_rect(Rect2(pos + Vector2(3, 3), Vector2(CELL - 6, CELL - 6)), Color("fff2c2"), false, 1.0)
		for d in dwarves:
			if d != null and d["target"] == i:
				draw_pixel_miner(pos, DWARF_TYPES[d["type"]]["color"])


func draw_ore_art(pos: Vector2, ore_name: String, ore_color: Color) -> void:
	var shapes := {
		"coal": [Vector2i(2, 2), Vector2i(3, 1), Vector2i(4, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(5, 3), Vector2i(4, 4)],
		"copper": [Vector2i(2, 3), Vector2i(3, 2), Vector2i(4, 1), Vector2i(4, 2), Vector2i(5, 2), Vector2i(3, 3), Vector2i(4, 4)],
		"iron": [Vector2i(2, 2), Vector2i(3, 1), Vector2i(4, 1), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 3), Vector2i(4, 4)],
		"gold": [Vector2i(2, 3), Vector2i(3, 2), Vector2i(4, 2), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(4, 4)],
	}
	for point in shapes.get(ore_name, []):
		var shard_pos := pos + Vector2(7 + point.x * 4, 5 + point.y * 4)
		draw_rect(Rect2(shard_pos + Vector2(2, 2), Vector2(5, 5)), ore_color.darkened(0.5))
		draw_rect(Rect2(shard_pos, Vector2(5, 5)), ore_color)
		draw_rect(Rect2(shard_pos + Vector2(1, 1), Vector2(2, 2)), ore_color.lightened(0.48))


func draw_pixel_miner(pos: Vector2, axe_color: Color) -> void:
	draw_rect(Rect2(pos + Vector2(27, 32), Vector2(12, 5)), Color("15141a"))
	draw_rect(Rect2(pos + Vector2(29, 17), Vector2(9, 14)), Color("7a392b"))
	draw_rect(Rect2(pos + Vector2(30, 10), Vector2(9, 9)), Color("e2b58b"))
	draw_rect(Rect2(pos + Vector2(28, 8), Vector2(13, 5)), axe_color)
	draw_rect(Rect2(pos + Vector2(26, 12), Vector2(17, 3)), Color("4a3022"))
	draw_rect(Rect2(pos + Vector2(33, 14), Vector2(2, 2)), Color("231d22"))
	draw_line(pos + Vector2(29, 24), pos + Vector2(20, 15), Color("80552f"), 3.0)
	draw_line(pos + Vector2(17, 14), pos + Vector2(24, 14), axe_color.lightened(0.25), 3.0)


func draw_inventory() -> void:
	var o := "Cevher  coal %d  copper %d  iron %d  gold %d" % [ores["coal"], ores["copper"], ores["iron"], ores["gold"]]
	var p := "Plate  copper %d  iron %d  gold %d" % [plates["copper"], plates["iron"], plates["gold"]]
	text(Vector2(30, 760), o, 22)
	text(Vector2(30, 795), p, 22, Color("8fd19e"))


func draw_furnace_panel() -> void:
	var recipe_names := {"copper": "Bakır", "iron": "Demir", "gold": "Altın"}
	var index := 0
	for furnace in furnaces:
		if floor_no < furnace["unlock"]:
			continue
		var y := 905 + index * 60
		draw_rect(Rect2(30, y, 660, 54), Color("2a2a36"))
		text(Vector2(42, y + 23), "Fırın %d" % (index + 1), 20)
		var active_recipe: String = furnace["active"]
		var selected_recipe: String = furnace["selected"]
		var status := "Bekliyor: %s" % recipe_names[selected_recipe]
		if active_recipe != "":
			status = "Üretiyor: %s" % recipe_names[active_recipe]
		text(Vector2(42, y + 45), status, 16, Color("aaaaaa"))
		var recipe_index := 0
		for recipe in RECIPES:
			if recipe_unlocked(recipe):
				var button_rect := Rect2(215 + recipe_index * 92, y + 7, 86, 40)
				draw_button(button_rect, recipe_names[recipe], true, select_furnace_recipe.bind(index, recipe), selected_recipe == recipe)
				recipe_index += 1
		var bar := Rect2(500, y + 15, 175, 24)
		draw_rect(bar, Color("14141a"))
		if active_recipe != "":
			var duration: float = RECIPES[active_recipe]["time"]
			var ratio: float = clampf(furnace["time"] / duration, 0.0, 1.0)
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), Color("3aa655"))
		else:
			var required: int = RECIPES[selected_recipe]["ore"]
			var waiting := "%d/%d ore, %d coal" % [ores[selected_recipe], required, ores["coal"]]
			draw_string(ThemeDB.fallback_font, Vector2(bar.position.x, bar.position.y + 18), waiting, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 14, Color("999999"))
		index += 1


func draw_market_panel() -> void:
	var i := 0
	for type in DWARF_TYPES:
		var info: Dictionary = DWARF_TYPES[type]
		var y := 905 + i * 100
		draw_rect(Rect2(30, y, 660, 90), Color("2a2a36"))
		text(Vector2(46, y + 36), "%s cücesi" % info["title"], 26, info["color"])
		var uses_money: bool = type == "copper" and not first_dwarf_purchased
		var cost: int = FIRST_DWARF_COST if uses_money else info["cost"]
		var price := "%d para" % cost if uses_money else "%d %s plate" % [cost, type]
		text(Vector2(46, y + 72), "Hasar %.1f / sn   Maliyet %s" % [info["dmg"], price], 20, Color("aaaaaa"))
		var full := free_slot() == -1
		var label := "Kutu dolu" if full else "Satın al"
		var can_afford: bool = money >= cost if uses_money else plates[type] >= cost
		draw_button(Rect2(500, y + 19, 175, 52), label, not full and can_afford, buy_dwarf.bind(type))
		i += 1


func draw_dwarf_panel() -> void:
	for i in 3:
		var y := 905 + i * 115
		draw_rect(Rect2(30, y, 660, 105), Color("2a2a36"))
		var d = dwarves[i]
		if d == null:
			text(Vector2(46, y + 40), "Boş cüce kutusu %d" % (i + 1), 24, Color("999999"))
			text(Vector2(46, y + 80), "Marketten cüce satın al", 20, Color("777777"))
		else:
			var info: Dictionary = DWARF_TYPES[d["type"]]
			text(Vector2(46, y + 40), "%s cücesi  Sv %d" % [info["title"], d["level"]], 26, info["color"])
			text(Vector2(46, y + 82), "Hasar: %.1f / sn" % dwarf_damage(d), 22, Color("aaaaaa"))
			var cost := dwarf_upgrade_cost(d)
			draw_button(Rect2(380, y + 28, 295, 50), "Güçlendir (%d %s plate)" % [cost, d["type"]], plates[d["type"]] >= cost, upgrade_dwarf.bind(i))


func draw_upgrade_panel() -> void:
	var infos := {
		"tap": "%.0f hasar" % tap_damage(),
		"crit_chance": "%%%d şans" % int(crit_chance() * 100),
		"crit_dmg": "x%.2f" % crit_mult(),
		"dwarf": "+%%%d" % (upgrade_levels["dwarf"] * 10),
	}
	for i in UPGRADES.size():
		var u: Dictionary = UPGRADES[i]
		var y := 905 + i * 88
		draw_rect(Rect2(30, y, 660, 80), Color("2a2a36"))
		text(Vector2(46, y + 34), "%s  Sv %d" % [u["title"], upgrade_levels[u["id"]]], 24)
		text(Vector2(46, y + 64), infos[u["id"]], 20, Color("aaaaaa"))
		var maxed: bool = upgrade_levels[u["id"]] >= u["max"]
		var cost := upgrade_cost(u)
		var label := "MAX" if maxed else "%s para" % fmt(cost)
		draw_button(Rect2(470, y + 14, 205, 52), label, not maxed and money >= cost, buy_upgrade.bind(u["id"]))


func draw_prestige_panel() -> void:
	var available := floor_no >= PRESTIGE_FLOOR
	text(Vector2(42, 925), "Puan: %d   Prestij: %d" % [prestige_points, prestige_count], 24, Color("ffe14d"))
	var reward_text := "Şu anki ödül: %d puan" % prestige_reward() if available else "Prestij 50. katta açılır."
	text(Vector2(42, 953), reward_text, 20, Color("aaaaaa"))
	for i in PRESTIGE_UPGRADES.size():
		var upgrade: Dictionary = PRESTIGE_UPGRADES[i]
		var y := 970 + i * 82
		var level: int = prestige_upgrades[upgrade["id"]]
		var maxed: bool = level >= upgrade["max"]
		var cost := prestige_upgrade_cost(upgrade)
		draw_rect(Rect2(30, y, 660, 72), Color("2a2a36"))
		text(Vector2(46, y + 30), "%s  Sv %d" % [upgrade["title"], level], 22)
		var effect := "+1 hasar" if upgrade["id"] == "damage" else "+%d%% gelir" % ((level + 1) * 10) if upgrade["id"] == "income" else "+100 başlangıç parası"
		text(Vector2(46, y + 58), effect, 18, Color("aaaaaa"))
		var label := "MAX" if maxed else "%d puan" % cost
		draw_button(Rect2(500, y + 12, 175, 50), label, not maxed and prestige_points >= cost, buy_prestige_upgrade.bind(upgrade["id"]))
	var prestige_label := "Prestij yap (+%d puan)" % prestige_reward() if available else "Prestij 50. katta açılır"
	draw_button(Rect2(160, 1215, 400, 52), prestige_label, available, perform_prestige)
