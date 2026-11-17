extends Control

@export var panel_bounds := Rect2(150, 106, 980, 510)

func configure(home: Control, message: String) -> void:
	var panel: Panel = home.modal("出站整备 · %s" % home.state.station, panel_bounds)
	var radiation: int = home.Rail.station_info(home.state.station).radiation
	home.label(panel, "区域辐射 · %s   /   外出上限 %d 秒" % [home.RADIATION[radiation], home.state.trip_limit()], Rect2(24, 83, 530, 28), 17, home.AMBER)
	home.label(panel, "防护服租用", Rect2(24, 133, 260, 30), 20)
	home.label(panel, "携带装备", Rect2(360, 133, 260, 30), 20)
	home.label(panel, "背包规格", Rect2(692, 133, 260, 30), 20)
	home.action(panel, "普通防护服    %d 度" % home.state.suit_rent(false), Rect2(24, 178, 263, 48), home.choose_gear.bind("heavy", false), not home.loadout.heavy)
	home.action(panel, "加强防护服    %d 度" % home.state.suit_rent(true), Rect2(24, 236, 263, 48), home.choose_gear.bind("heavy", true), home.loadout.heavy)
	home.wrapped(panel, "超时赔偿普通 300 度、加强 500 度。高辐射区需加强防护服。", Rect2(24, 305, 263, 62), 15, home.MUTED)
	home.label(panel, "手电筒必带 · %s" % home.installed_battery_text(), Rect2(360, 176, 263, 26), 17, home.MINT)
	home.swap_button(panel, Rect2(360, 211, 263, 39))
	home.action(panel, "撬棍   %s" % ("已携带" if home.loadout.crowbar else "未携带"), Rect2(360, 259, 263, 40), home.choose_gear.bind("crowbar", not home.loadout.crowbar), home.loadout.crowbar)
	var carry_wrench: bool = home.loadout.get("wrench", false)
	var wrench: Button = home.action(panel, "扳手   %s" % ("已携带" if carry_wrench else "未携带"), Rect2(360, 309, 263, 40), home.choose_gear.bind("wrench", not carry_wrench), carry_wrench)
	wrench.disabled = home.state.auto_repair_level == 0
	wrench.tooltip_text = "完成同济大学汽修一级培训后获得。"
	home.label(panel, "按 1 照明 · 每秒耗电 5%", Rect2(360, 353, 263, 24), 14, home.MUTED)
	home.action(panel, "小背包    5 × 4", Rect2(692, 178, 263, 48), home.choose_gear.bind("wide", false), not home.loadout.wide)
	home.action(panel, "大背包    6 × 5", Rect2(692, 236, 263, 48), home.choose_gear.bind("wide", true), home.loadout.wide)
	home.wrapped(panel, "出发前可在柜子里腾出空间。", Rect2(692, 308, 263, 49), 15, home.MUTED)
	home.plate(panel, Rect2(24, 385, 932, 1), home.BORDER)
	home.label(panel, "电力余额  %s 度" % str(snappedf(home.state.account, 0.1)), Rect2(24, 429, 247, 44), 19, home.AMBER)
	home.status = home.label(panel, "", Rect2(280, 421, 405, 60), 15, home.AMBER)
	home.status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	home.report(message)
	var rent: int = home.state.suit_rent(home.loadout.heavy)
	var shortfall: float = home.state.credit_shortfall(rent)
	var caption := "确认出发 · %d 度" % rent
	if shortfall > 0.0:
		caption += " · 欠 %s 度" % home.energy_text(shortfall)
	home.action(panel, caption, Rect2(700, 427, 256, 46), home.confirm_departure, true)
