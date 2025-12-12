/* 
Talking statues. A means of giving communication to certain spheres 
(Church, Mercenaries) without overloading them into the SCOM ecosystem.

Ideally, these machines will encourage gathering in a "centralized" area.
Hopefully they are more useful than just writing a letter via HERMES. 
*/

/obj/structure/roguemachine/talkstatue
	name = "talking statue"
	desc = "Don't map this one! Map the others!"
	icon = 'icons/roguetown/misc/machines.dmi'
	icon_state = "goldvendor" //placeholder
	density = TRUE
	anchored = TRUE
	max_integrity = 0

/obj/structure/roguemachine/talkstatue/mercenary
	name = "mercenary statue"
	desc = "A weathered stone statue depicting a warrior in foreign garb. A faint inscription reads: 'Silver for one, Gold for all.'"
	icon_state = "goldvendor" //TODO: Get proper sprite
	var/list/mercenary_status = list() // Stores: list(mob.key = list("status" = status, "mob" = mob, "message" = message))
	var/list/pending_registrations = list() // Stores: list(mob.key = mob) for remote registrations that haven't expired
	var/message_char_limit = 300 // Character limit for coin messages

/obj/structure/roguemachine/talkstatue/mercenary/Initialize()
	. = ..()
	if(SSroguemachine.mercenary_statue == null) // Only one mapped mercenary statue
		SSroguemachine.mercenary_statue = src

/obj/structure/roguemachine/talkstatue/mercenary/attack_hand(mob/living/carbon/human/user)
	. = ..()
	if(.)
		return

	// Cull invalid mercenary references first
	cull_invalid_mercenaries()

	// Check if the user is a mercenary
	if(user.mind && user.mind.assigned_role == "Mercenary")
		// Show UI with option to cycle status
		show_mercenary_ui(user, is_mercenary = TRUE)
	else
		// Show read-only UI for non-mercenaries
		show_mercenary_ui(user, is_mercenary = FALSE)

/obj/structure/roguemachine/talkstatue/mercenary/attackby(obj/item/P, mob/living/carbon/human/user, params)
	// Proximity check - user must be adjacent to the statue
	if(!Adjacent(user))
		to_chat(user, span_warning("I need to be closer to the statue."))
		return

	if(istype(P, /obj/item/roguecoin/silver))
		// Silver coin - message a specific mercenary
		var/obj/item/roguecoin/silver/coin = P
		if(coin.quantity > 1)
			to_chat(user, span_warning("I need to use a single ziliqua."))
			return
		message_single_mercenary(user, coin)
		return

	if(istype(P, /obj/item/roguecoin/gold))
		// Gold coin - broadcast to all mercenaries
		var/obj/item/roguecoin/gold/coin = P
		if(coin.quantity > 1)
			to_chat(user, span_warning("I need to use a single zenar."))
			return
		broadcast_to_mercenaries(user, coin)
		return

	return ..()

/obj/structure/roguemachine/talkstatue/mercenary/proc/cycle_mercenary_status(mob/living/carbon/human/user)
	// Get or create the status entry for this mercenary
	var/list/merc_data = mercenary_status[user.key]
	if(!merc_data)
		merc_data = list("status" = null, "mob" = user, "message" = "")
		mercenary_status[user.key] = merc_data

	var/current_status = merc_data["status"]
	var/new_status

	switch(current_status)
		if(null, "Available")
			new_status = "Contracted"
		if("Contracted")
			new_status = "Do not Disturb"
		if("Do not Disturb")
			new_status = "Available"

	merc_data["status"] = new_status
	merc_data["mob"] = user // Update mob reference
	to_chat(user, span_notice("You set your status to: <b>[new_status]</b>"))
	playsound(loc, 'sound/misc/beep.ogg', 100, FALSE, -1)

/obj/structure/roguemachine/talkstatue/mercenary/proc/message_single_mercenary(mob/living/carbon/human/sender, obj/item/roguecoin/silver/coin)
	// Get list of available mercenaries from the status list
	var/list/available_mercenaries = list()

	for(var/merc_key in mercenary_status)
		var/list/merc_data = mercenary_status[merc_key]
		var/mob/living/carbon/human/merc = merc_data["mob"]

		// Validate the mercenary is still valid
		if(!merc || merc.stat == DEAD)
			continue
		if(merc_data["status"] == "Do not Disturb")
			continue

		var/status_text = merc_data["status"] || "Available"
		var/display_name = "[merc.real_name] ([status_text])"
		available_mercenaries[display_name] = merc

	if(!available_mercenaries.len)
		to_chat(sender, span_warning("No mercenaries are currently available."))
		return

	var/choice = input(sender, "Which mercenary do you wish to contact?", "Mercenary Contact") as null|anything in available_mercenaries
	if(!choice)
		return

	var/mob/living/carbon/human/target_merc = available_mercenaries[choice]

	// Proximity check again before allowing message input
	if(!Adjacent(sender))
		to_chat(sender, span_warning("I need to stay close to the statue."))
		return

	var/message = stripped_input(sender, "What message do you wish to send? (Max [message_char_limit] characters)", "Mercenary Contact", "", message_char_limit)
	if(!message)
		return

	// Final proximity and coin checks
	if(!Adjacent(sender))
		to_chat(sender, span_warning("I moved too far from the statue."))
		return

	if(!(coin in sender.held_items))
		to_chat(sender, span_warning("You need to hold the ziliqua!"))
		return

	// Consume the coin
	qdel(coin)
	playsound(loc, 'sound/foley/coinphy (1).ogg', 100, FALSE, -1)

	// Send the message
	to_chat(target_merc, span_boldnotice("The statue whispers in your mind: <i>[message]</i> - [sender.real_name]"))
	to_chat(sender, span_notice("Your message has been sent to [target_merc.real_name]."))
	playsound(target_merc.loc, 'sound/misc/notice (2).ogg', 100, FALSE, -1)

	// Admin logging - log on both sender and recipient like mindlink does
	sender.log_talk(message, LOG_SAY, tag="mercenary statue (to [key_name(target_merc)])")
	target_merc.log_talk(message, LOG_SAY, tag="mercenary statue (from [key_name(sender)])", log_globally=FALSE)

/obj/structure/roguemachine/talkstatue/mercenary/proc/broadcast_to_mercenaries(mob/living/carbon/human/sender, obj/item/roguecoin/gold/coin)
	// Proximity check before allowing message input
	if(!Adjacent(sender))
		to_chat(sender, span_warning("I need to stay close to the statue."))
		return

	var/message = stripped_input(sender, "What message do you wish to broadcast to all mercenaries? (Max [message_char_limit] characters)", "Mercenary Broadcast", "", message_char_limit)
	if(!message)
		return

	// Final proximity and coin checks
	if(!Adjacent(sender))
		to_chat(sender, span_warning("I moved too far from the statue."))
		return

	if(!(coin in sender.held_items))
		to_chat(sender, span_warning("You need to hold the zenar!"))
		return

	// Count how many mercenaries will receive this from the status list (excluding DND)
	var/merc_count = 0
	var/list/recipient_keys = list() // Track recipients for logging
	for(var/merc_key in mercenary_status)
		var/list/merc_data = mercenary_status[merc_key]
		var/mob/living/carbon/human/merc = merc_data["mob"]

		if(!merc || merc.stat == DEAD)
			continue
		// Skip Do not Disturb mercenaries
		if(merc_data["status"] == "Do not Disturb")
			continue
		merc_count++
		recipient_keys += key_name(merc)

	if(merc_count == 0)
		to_chat(sender, span_warning("There are no mercenaries available to broadcast to."))
		return

	// Consume the coin
	qdel(coin)
	playsound(loc, 'sound/foley/coinphy (1).ogg', 100, FALSE, -1)

	// Broadcast the message to all mercenaries in the status list (excluding DND)
	for(var/merc_key in mercenary_status)
		var/list/merc_data = mercenary_status[merc_key]
		var/mob/living/carbon/human/merc = merc_data["mob"]

		if(!merc || merc.stat == DEAD)
			continue
		// Skip Do not Disturb mercenaries
		if(merc_data["status"] == "Do not Disturb")
			continue

		to_chat(merc, span_boldannounce("The mercenary statue calls out: <i>[message]</i> - [sender.real_name]"))
		playsound(merc.loc, 'sound/misc/notice (2).ogg', 100, FALSE, -1)

	to_chat(sender, span_notice("Your message has been broadcast to [merc_count] mercenary\s."))
	say("The message echoes through the mercenary network...")

	// Admin logging for broadcast - log on sender with all recipients
	sender.log_talk(message, LOG_SAY, tag="mercenary statue broadcast (to [recipient_keys.Join(", ")])")

/obj/structure/roguemachine/talkstatue/mercenary/proc/cull_invalid_mercenaries()
	// Remove mercenaries whose mob references are invalid (logged out, far traveled, etc.)
	var/list/keys_to_remove = list()

	for(var/merc_key in mercenary_status)
		var/list/merc_data = mercenary_status[merc_key]
		var/mob/living/carbon/human/merc = merc_data["mob"]

		// Check if mob is invalid (deleted, null, or client disconnected and not coming back)
		if(!merc || QDELETED(merc) || !merc.ckey)
			keys_to_remove += merc_key

	// Remove all invalid entries
	for(var/key in keys_to_remove)
		mercenary_status -= key

/obj/structure/roguemachine/talkstatue/mercenary/proc/show_mercenary_ui(mob/living/carbon/human/user, is_mercenary = FALSE)
	user.changeNext_move(CLICK_CD_INTENTCAP)
	playsound(loc, 'sound/misc/keyboard_enter.ogg', 100, FALSE, -1)

	var/contents = ""
	contents += "<center><b>MERCENARY ROSTER</b></center>"
	contents += "<hr>"

	if(is_mercenary)
		// Show current status and cycle button for mercenaries
		var/list/merc_data = mercenary_status[user.key]
		var/current_status = merc_data ? merc_data["status"] : null
		var/status_display = current_status || "Not Registered"
		var/custom_message = merc_data ? merc_data["message"] : ""

		contents += "<center>"
		contents += "Your current status: <b>[status_display]</b><br>"
		contents += "<a href='?src=[REF(src)];cycle_status=1'>\[Change Status\]</a> | "
		contents += "<a href='?src=[REF(src)];edit_message=1'>\[Edit Message\]</a><br>"
		if(custom_message)
			contents += "<i>\"[custom_message]\"</i>"
		else
			contents += "<i>No custom message set</i>"
		contents += "</center><hr>"

	// Display list of mercenaries
	contents += "<b>Registered Mercenaries:</b><br>"

	if(!mercenary_status.len)
		contents += "<i>No mercenaries have registered yet.</i><br>"
	else
		var/merc_count = 0
		var/available_count = 0
		var/contracted_count = 0
		var/dnd_count = 0

		// Sort mercenaries by status
		var/list/available_mercs = list()
		var/list/contracted_mercs = list()
		var/list/dnd_mercs = list()

		for(var/merc_key in mercenary_status)
			var/list/merc_data = mercenary_status[merc_key]
			var/mob/living/carbon/human/merc = merc_data["mob"]

			if(!merc)
				continue

			merc_count++
			var/status = merc_data["status"] || "Available"
			var/custom_msg = merc_data["message"] || ""
			var/advjob_title = merc.advjob || "Mercenary"

			switch(status)
				if("Available")
					available_count++
					available_mercs += list(list("name" = merc.real_name, "status" = status, "message" = custom_msg, "advjob" = advjob_title))
				if("Contracted")
					contracted_count++
					contracted_mercs += list(list("name" = merc.real_name, "status" = status, "message" = custom_msg, "advjob" = advjob_title))
				if("Do not Disturb")
					dnd_count++
					dnd_mercs += list(list("name" = merc.real_name, "status" = status, "message" = custom_msg, "advjob" = advjob_title))

		// Summary counts
		contents += "<br><center>"
		contents += "Total: <b>[merc_count]</b> | "
		contents += "<span style='color:green;'>Available: [available_count]</span> | "
		contents += "<span style='color:orange;'>Contracted: [contracted_count]</span> | "
		contents += "<span style='color:red;'>DND: [dnd_count]</span>"
		contents += "</center><br><hr>"

		// Display Available mercenaries
		if(available_mercs.len)
			contents += "<b><span style='color:green;'>Available for Contract:</span></b><br>"
			for(var/list/merc_info in available_mercs)
				contents += "  <b>-</b> [merc_info["name"]] <span style='color:#888;'>([merc_info["advjob"]])</span><br>"
				if(merc_info["message"])
					contents += "    <i>\"[merc_info["message"]]\"</i><br>"
			contents += "<br>"

		// Display Contracted mercenaries
		if(contracted_mercs.len)
			contents += "<b><span style='color:orange;'>Currently Contracted:</span></b><br>"
			for(var/list/merc_info in contracted_mercs)
				contents += "  <b>-</b> [merc_info["name"]] <span style='color:#888;'>([merc_info["advjob"]])</span><br>"
				if(merc_info["message"])
					contents += "    <i>\"[merc_info["message"]]\"</i><br>"
			contents += "<br>"

		// Display Do not Disturb mercenaries
		if(dnd_mercs.len)
			contents += "<b><span style='color:red;'>Do Not Disturb:</span></b><br>"
			for(var/list/merc_info in dnd_mercs)
				contents += "  <b>-</b> [merc_info["name"]] <span style='color:#888;'>([merc_info["advjob"]])</span><br>"
				if(merc_info["message"])
					contents += "    <i>\"[merc_info["message"]]\"</i><br>"

	contents += "<hr>"
	contents += "<center><i>Silver for one, Gold for all.</i></center>"

	var/datum/browser/popup = new(user, "MERCSTATUE", "", 400, 500)
	popup.set_content(contents)
	popup.open()

/obj/structure/roguemachine/talkstatue/mercenary/Topic(href, href_list)
	. = ..()

	if(href_list["cycle_status"])
		// Verify user is a mercenary and close to the statue
		if(!ishuman(usr))
			return
		var/mob/living/carbon/human/H = usr
		if(!H.mind || H.mind.assigned_role != "Mercenary")
			to_chat(H, span_warning("You are not a mercenary."))
			return

		// Cycle their status
		cycle_mercenary_status(H)

		// Refresh the UI
		show_mercenary_ui(H, is_mercenary = TRUE)
		return

	if(href_list["edit_message"])
		// Verify user is a mercenary
		if(!ishuman(usr))
			return
		var/mob/living/carbon/human/H = usr
		if(!H.mind || H.mind.assigned_role != "Mercenary")
			to_chat(H, span_warning("You are not a mercenary."))
			return

		// Get or create their data
		var/list/merc_data = mercenary_status[H.key]
		if(!merc_data)
			merc_data = list("status" = "Available", "mob" = H, "message" = "")
			mercenary_status[H.key] = merc_data

		// Prompt for custom message
		var/current_msg = merc_data["message"] || ""
		var/new_msg = stripped_input(H, "Enter your custom message (max 200 characters):", "Mercenary Message", current_msg, 200)

		if(new_msg != null) // Allow empty string to clear message
			merc_data["message"] = new_msg
			to_chat(H, span_notice("Your mercenary message has been updated."))
			playsound(loc, 'sound/misc/beep.ogg', 100, FALSE, -1)

		// Refresh the UI
		show_mercenary_ui(H, is_mercenary = TRUE)
		return

	if(href_list["register"])
		var/mob/living/carbon/human/H = locate(href_list["register"])
		if(!H)
			return

		// Verify the user is still valid and pending
		if(!pending_registrations[H.key])
			to_chat(usr, span_warning("That registration link has expired."))
			return

		if(H.mind?.assigned_role != "Mercenary")
			to_chat(usr, span_warning("You are no longer a mercenary."))
			return

		if(!H.mind)
			return

		// Register the mercenary remotely
		var/list/merc_data = list("status" = "Available", "mob" = H, "message" = "")
		mercenary_status[H.key] = merc_data

		// Remove from pending
		pending_registrations -= H.key

		to_chat(H, span_boldnotice("You have connected to the mercenary statue network! You are now listed as <b>Available</b>."))
		to_chat(H, span_notice("You can visit the statue in person to change your status."))
		playsound(H.loc, 'sound/misc/notice (2).ogg', 100, FALSE, -1)

/obj/structure/roguemachine/talkstatue/mercenary/proc/expire_registration(key)
	if(pending_registrations[key])
		pending_registrations -= key

/obj/structure/roguemachine/talkstatue/church
	name = "church statue"
	desc = "A blessed stone statue radiating divine presence."
	icon_state = "goldvendor" //TODO: Get proper sprite

/obj/structure/roguemachine/talkstatue/church/Initialize()
	. = ..()
	if(SSroguemachine.church_statue == null) // Only one mapped church statue
		SSroguemachine.church_statue = src

//Code goes here
