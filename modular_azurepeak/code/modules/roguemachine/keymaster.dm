/obj/structure/roguemachine/keymaster
	name = "KEYMASTER"
	desc = "They call it 'KEYMASTER'... Whatever it may touch, turns to keys in its clutch."
	icon = 'icons/roguetown/misc/machines.dmi'
	icon_state = "crown_meister" //
	density = TRUE
	blade_dulling = DULLING_BASH
	max_integrity = 0
	anchored = TRUE
	layer = BELOW_OBJ_LAYER
	light_outer_range = 3
	light_color = "#cfb53b"
	var/list/held_items = list()
	var/locked = FALSE
	var/budget = 0
	var/secret_budget = 0
	var/recent_payments = 0
	var/last_payout = 0
	var/drugrade_flags
