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


# ---------------------------------------------------------------- v12.4: дерево и мутации подробнее

func test_every_node_and_perk_is_well_formed() -> void:
	var ids := {}
	for n: Dictionary in Skills.TREE:
		assert_false(ids.has(n["id"]), "узел %s уникален" % n["id"])
		ids[n["id"]] = true
		assert_between(int(n["branch"]), 0, Skills.BRANCHES.size() - 1)
		assert_gt(int(n["max"]), 0, "%s: хотя бы один ранг" % n["id"])
		assert_gt(int(n["cost"]), 0, "%s: не бесплатный" % n["id"])
		assert_ne(String(n["desc"]), "", "%s: есть описание" % n["id"])
	var perk_ids := {}  # у мутации и узла может быть общий смысл (гибкость) — это разные списки
	for p: Dictionary in Skills.PERKS:
		assert_false(perk_ids.has(p["id"]), "мутация %s уникальна" % p["id"])
		perk_ids[p["id"]] = true
		assert_between(int(p.get("rarity", 0)), 0, Skills.RARITY.size() - 1)
		assert_eq(Skills.perk(p["id"]), p)
	assert_true(Skills.perk("нет-такой").is_empty())
	assert_true(Skills.node("нет-такого").is_empty() or not Skills.node("нет-такого").has("id"))


func test_perk_weights_follow_rarity_and_nose() -> void:
	var common: Dictionary = Skills.PERKS[0]
	var legend := {}
	for p: Dictionary in Skills.PERKS:
		if int(p.get("rarity", 0)) == 2:
			legend = p
	assert_eq(Skills.perk_weight(common, 2), Skills.RARITY[0]["weight"], "нюх не трогает обычные")
	assert_eq(Skills.perk_weight(legend, 0), Skills.RARITY[2]["weight"])
	assert_eq(Skills.perk_weight(legend, 2), Skills.RARITY[2]["weight"] * 3.0, "два ранга нюха — втрое чаще")


func test_roll_never_repeats_and_skips_taken_uniques() -> void:
	var taken := {}
	for p: Dictionary in Skills.PERKS:
		if p.get("unique", false):
			taken[p["id"]] = 1
	for i in 50:
		var hand := Skills.roll_perks(4, taken)
		assert_len(hand, 4)
		var seen := {}
		for p: Dictionary in hand:
			assert_false(seen.has(p["id"]), "в раздаче без повторов")
			seen[p["id"]] = true
			assert_false(taken.has(p["id"]), "взятые уникальные не выпадают")


func test_roll_with_tiny_pool_gives_what_is_left() -> void:
	var taken := {}
	for p: Dictionary in Skills.PERKS:
		taken[p["id"]] = 1
	var hand := Skills.roll_perks(3, taken)
	for p: Dictionary in hand:
		assert_false(p.get("unique", false), "остались только повторяемые")
	assert_true(hand.size() <= 3)


func test_mods_from_every_perk() -> void:
	var m := Skills.mods({"tank": 1, "regen": 1, "flex": 1, "sprint": 1, "resist": 1, "charges": 1, "knockout": 1,
		"burst": 1, "leech": 1, "hoarder": 1, "forkmaster": 1, "berserk": 1, "phoenix": 1}, false)
	assert_near(m["stamina_max"], 1.25, 0.001)
	assert_near(m["regen"], 1.3, 0.001)
	assert_near(m["turn"], 1.2, 0.001)
	assert_near(m["sprint"], 1.15, 0.001)
	assert_near(m["resist"], 0.6, 0.001)
	assert_eq(m["charges"], 2)
	assert_eq(m["knockout"], 3)
	assert_true(m["burst"] and m["berserk"] and m["phoenix"])
	assert_eq(m["leech"], 12)
	assert_near(m["scales_mult"], 1.5, 0.001)
	assert_eq(m["fork_every"], 1)
	var off := Skills.mods({"tank": 1, "phoenix": 1}, true)
	assert_eq(off["stamina_max"], 1.0, "на Ультра мутации не действуют")
	assert_false(off["phoenix"])


func test_scale_rewards_by_difficulty_and_clamp() -> void:
	assert_eq(Skills.scales_for_run(10.0, 0), 10)
	assert_eq(Skills.scales_for_run(10.0, 3), 30, "Ультра — втрое")
	assert_eq(Skills.scales_for_run(10.0, 99), 30, "сложность вне таблицы — как последняя")
	assert_eq(Skills.scales_for_run(8.333333, 1, 3.0), 37, "дробные множители без потерь на округлении")


func test_fourth_card_skill() -> void:
	Skills.reset_all()
	assert_eq(Skills.perk_cards(), 3)
	Skills.ranks["lucky"] = 1
	assert_eq(Skills.perk_cards(), 4, "«Четвёртая карта» — четыре карточки")
	Skills.reset_all()
