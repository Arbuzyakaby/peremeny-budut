extends "res://tests/test_case.gd"
## Древо навыков: цены, открытие веток, покупка, сброс, сохранение, модификаторы, улучшения.

const Combat = preload("res://scripts/core/combat.gd")
const Balance = preload("res://scripts/core/balance.gd")
const Snake = preload("res://scripts/entities/snake.gd")


func before_each() -> void:
	use_temp_storage()


func test_cost_grows_with_rank() -> void:
	Skills.scales = 1000
	var first := Skills.cost("hide")
	assert_true(Skills.buy("hide"))
	assert_eq(Skills.cost("hide"), first * 2, "второй ранг вдвое дороже")


func test_first_node_of_branch_is_open() -> void:
	for id in ["hide", "flex", "hoard"]:
		assert_true(Skills.unlocked(id), id + " открыт")
	for id in ["lungs", "sprinter", "thrift", "molt", "jaws"]:
		assert_false(Skills.unlocked(id), id + " закрыт")


func test_buy_requires_enough_scales() -> void:
	Skills.scales = Skills.cost("hide") - 1
	assert_false(Skills.buy("hide"))
	assert_eq(Skills.rank("hide"), 0)
	Skills.scales += 1
	assert_true(Skills.buy("hide"))
	assert_eq(Skills.scales, 0)


func test_buying_opens_next_node() -> void:
	Skills.scales = 100
	assert_false(Skills.unlocked("lungs"))
	Skills.buy("hide")
	assert_true(Skills.unlocked("lungs"))


func test_rank_is_capped() -> void:
	Skills.scales = 10000
	while Skills.buy("hoard"):
		pass
	assert_eq(Skills.rank("hoard"), Skills.node("hoard")["max"])
	assert_true(Skills.maxed("hoard"))
	assert_false(Skills.can_buy("hoard"))


func test_reset_refunds_everything() -> void:
	Skills.scales = 500
	Skills.buy("hide")
	Skills.buy("hide")
	Skills.buy("lungs")
	Skills.buy("flex")
	Skills.reset_all()
	assert_eq(Skills.scales, 500, "все чешуйки вернулись")
	for n in Skills.TREE:
		assert_eq(Skills.rank(n["id"]), 0)


func test_progress_survives_reload() -> void:
	Skills.scales = 100
	Skills.buy("hide")
	var left := Skills.scales
	Skills.load_progress()
	assert_eq(Skills.rank("hide"), 1)
	assert_eq(Skills.scales, left)


func test_broken_save_is_clamped() -> void:
	SaveData.write_section("skills", {"scales": 5, "hide": 99})
	Skills.load_progress()
	assert_eq(Skills.rank("hide"), Skills.node("hide")["max"])


func test_mods_disabled_on_ultra() -> void:
	Skills.scales = 1000
	Skills.buy("hide")
	Skills.buy("flex")
	var m := Skills.mods({"tank": 2, "charges": 1}, true)
	assert_eq(m["lives"], 0)
	assert_near(m["turn"], 1.0)
	assert_near(m["stamina_max"], 1.0)
	assert_eq(m["charges"], 0)


func test_mods_combine_tree_and_perks() -> void:
	Skills.scales = 1000
	Skills.buy("hide")
	Skills.buy("lungs")
	Skills.buy("flex")
	var m := Skills.mods({"tank": 1, "flex": 1, "knockout": 1}, false)
	assert_eq(m["lives"], 1)
	assert_near(m["stamina_max"], 1.0 + 0.2 + 0.25)
	assert_near(m["turn"], 1.0 + 0.12 + 0.2)
	assert_eq(m["knockout"], 3)


func test_scales_for_run_uses_difficulty_multiplier() -> void:
	assert_eq(Skills.scales_for_run(20.0, 0), 20)
	assert_eq(Skills.scales_for_run(20.0, 1), 30)
	assert_eq(Skills.scales_for_run(20.0, 3), 60)


func test_roll_perks_gives_three_different() -> void:
	for i in 20:
		var cards := Skills.roll_perks()
		assert_eq(cards.size(), 3)
		assert_true(cards[0]["id"] != cards[1]["id"] and cards[1]["id"] != cards[2]["id"] and cards[0]["id"] != cards[2]["id"])


# ---------------------------------------------------------------- v8.2: ветка «Добыча» и мутации

func test_tree_is_four_by_five() -> void:
	assert_eq(Skills.TREE.size(), Skills.BRANCHES.size() * Skills.ROWS)
	for i in Skills.TREE.size():
		assert_eq(int(Skills.TREE[i]["branch"]), i / Skills.ROWS, Skills.TREE[i]["id"])
	for id in ["hide", "flex", "hoard", "greed"]:
		assert_true(Skills.unlocked(id), id + " открыт")


func test_loot_branch_mods() -> void:
	Skills.scales = 10000
	Skills.buy("greed")
	Skills.buy("gloat")
	Skills.buy("nose")
	Skills.buy("lucky")
	var m := Skills.mods({"hoarder": 1}, false)
	assert_near(m["scales_mult"], 1.15 * 1.5)
	assert_near(m["score_mult"], 1.1)
	assert_eq(m["nose"], 1)
	assert_eq(Skills.perk_cards(), 4)
	assert_eq(Skills.scales_for_run(20.0, 0, m["scales_mult"]), int(20.0 * 1.15 * 1.5))


func test_unique_mutations_not_repeated() -> void:
	for i in 30:
		for p in Skills.roll_perks(4, {"berserk": 1, "leech": 1, "burst": 1, "phoenix": 1}, 2):
			assert_false(p["id"] in ["berserk", "leech", "burst", "phoenix"], p["id"])


func test_nose_raises_rare_weight() -> void:
	var rare: Dictionary = Skills.perk("berserk")
	assert_gt(Skills.perk_weight(rare, 2), Skills.perk_weight(rare, 0))
	assert_near(Skills.perk_weight(Skills.perk("tank"), 2), Skills.perk_weight(Skills.perk("tank"), 0))


func test_berserk_makes_attacks_free_and_stronger() -> void:
	var on := {"berserk_on": true}
	assert_near(Combat.ability_cost(2, on), 0.0)
	assert_near(Combat.boss_chip("fork", on), Combat.boss_chip("fork", {}) * 1.5)


func test_loot_adds_fork_charge() -> void:
	assert_eq(Combat.ability_charges(10, {"loot": 1}), int(Balance.ABILITIES[10]["charges"]) + 1)
	assert_eq(Combat.ability_charges(2, {"loot": 1}), int(Balance.ABILITIES[2]["charges"]), "медведям — нет")


func test_phoenix_revives_once() -> void:
	var s := Snake.new()
	s.max_lives = 3
	s.lives = 1
	s.apply_mods({"phoenix": true})
	s.take_damage(1)
	assert_true(s.alive)
	assert_eq(s.lives, 2)
	s.invuln = 0.0
	s.take_damage(2)
	assert_false(s.alive, "второй раз не спасает")
	s.free()
