/datum/computer_file/program/card_mod
	filename = "cardmod"
	filedesc = "ID card modification program"
	program_icon_state = "id"
	extended_desc = "Program for programming employee ID cards to access parts of the station."
	transfer_access = ACCESS_CHANGE_IDS
	requires_ntnet = 0
	size = 8
	var/is_centcom = 0
	var/mode = 0
	var/printing = 0

	//Cooldown for closing positions in seconds
	//if set to -1: No cooldown... probably a bad idea
	//if set to 0: Not able to close "original" positions. You can only close positions that you have opened before
	var/change_position_cooldown = 60
	//Jobs you cannot open new positions for
	var/list/blacklisted = list(
		/datum/job/ai,
		/datum/job/cyborg,
		/datum/job/captain,
		/datum/job/hop,
		/datum/job/hos,
		/datum/job/chief_engineer,
		/datum/job/rd,
		/datum/job/cmo,
		/datum/job/judge,
		/datum/job/blueshield,
		/datum/job/nanotrasenrep,
		/datum/job/pilot,
		/datum/job/brigdoc,
		/datum/job/mechanic,
		/datum/job/barber,
		/datum/job/chaplain,
		/datum/job/ntnavyofficer,
		/datum/job/ntspecops,
		/datum/job/ntinstructor,
		/datum/job/civilian,
		/datum/job/syndicateofficer,
		/datum/job/explorer // blacklisted so that HOPs don't try prioritizing it, then wonder why that doesn't work
	)

	//The scaling factor of max total positions in relation to the total amount of people on board the station in %
	var/max_relative_positions = 30 //30%: Seems reasonable, limit of 6 @ 20 players

	//This is used to keep track of opened positions for jobs to allow instant closing
	//Assoc array: "JobName" = (int)<Opened Positions>
	var/list/opened_positions = list()

/datum/computer_file/program/card_mod/proc/is_authenticated(var/mob/user)
	if(user.can_admin_interact())
		return 1
	if(computer)
		var/obj/item/computer_hardware/card_slot/card_slot = computer.all_components[MC_CARD]
		if(card_slot)
			var/obj/item/card/id/auth_card = card_slot.stored_card2
			if(auth_card)
				return check_access(auth_card)
	return 0

/datum/computer_file/program/card_mod/proc/check_access(obj/item/I)
	if(ACCESS_CHANGE_IDS in I.GetAccess())
		return 1
	return 0

/datum/computer_file/program/card_mod/proc/get_target_rank()
	if(computer)
		var/obj/item/computer_hardware/card_slot/card_slot = computer.all_components[MC_CARD]
		if(card_slot)
			var/obj/item/card/id/id_card = card_slot.stored_card
			if(id_card && id_card.assignment)
				return id_card.assignment
	return "Unassigned"

/datum/computer_file/program/card_mod/proc/format_job_slots()
	var/list/formatted = list()
	for(var/datum/job/job in SSjobs.occupations)
		if(job_blacklisted(job))
			continue
		formatted.Add(list(list(
			"title" = job.title,
			"current_positions" = job.current_positions,
			"total_positions" = job.total_positions,
			"can_open" = can_open_job(job),
			"can_close" = can_close_job(job),
			"can_prioritize" = can_prioritize_job(job)
		)))

	return formatted

/datum/computer_file/program/card_mod/proc/format_card_skins(list/card_skins)
	var/list/formatted = list()
	for(var/skin in card_skins)
		formatted.Add(list(list(
			"display_name" = get_skin_desc(skin),
			"skin" = skin)))

	return formatted


/datum/computer_file/program/card_mod/proc/job_blacklisted(datum/job/job)
	return (job.type in blacklisted)


//Logic check for if you can open the job
/datum/computer_file/program/card_mod/proc/can_open_job(datum/job/job)
	if(job)
		if(!job_blacklisted(job))
			if((job.total_positions <= GLOB.player_list.len * (max_relative_positions / 100)))
				var/delta = (world.time / 10) - GLOB.time_last_changed_position
				if((change_position_cooldown < delta) || (opened_positions[job.title] < 0))
					return 1
				return -2
			return -1
	return 0

//Logic check for if you can close the job
/datum/computer_file/program/card_mod/proc/can_close_job(datum/job/job)
	if(job)
		if(!job_blacklisted(job))
			if(job.total_positions > job.current_positions)
				var/delta = (world.time / 10) - GLOB.time_last_changed_position
				if((change_position_cooldown < delta) || (opened_positions[job.title] > 0))
					return 1
				return -2
			return -1
	return 0

/datum/computer_file/program/card_mod/proc/can_prioritize_job(datum/job/job)
	if(job)
		if(!job_blacklisted(job))
			if(job in SSjobs.prioritized_jobs)
				return 2
			else
				if(SSjobs.prioritized_jobs.len >= 3)
					return 0
				if(job.total_positions <= job.current_positions)
					return 0
				return 1
	return -1

/datum/computer_file/program/card_mod/proc/format_jobs(list/jobs, targetrank, list/jobformats)
	var/obj/item/computer_hardware/card_slot/card_slot = computer.all_components[MC_CARD]
	if(!card_slot || !card_slot.stored_card)
		return null
	var/list/formatted = list()
	for(var/job in jobs)
		formatted.Add(list(list(
			"display_name" = replacetext(job, "&nbsp", " "),
			"target_rank" = targetrank,
			"job" = job,
			"jlinkformat" = jobformats[job] ? jobformats[job] : null)))
	return formatted


/datum/computer_file/program/card_mod/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open = 1)
	ui = SSnanoui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		var/datum/asset/assets = get_asset_datum(/datum/asset/simple/headers)
		assets.send(user)
		ui = new(user, src, ui_key, "card_prog.tmpl", "ID card modification program", 775, 700)
		ui.set_layout_key("program")
		ui.open()

/datum/computer_file/program/card_mod/Topic(href, href_list)
	if(..())
		return 1

	var/obj/item/computer_hardware/card_slot/card_slot
	var/obj/item/computer_hardware/printer/printer
	if(computer)
		card_slot = computer.all_components[MC_CARD]
		printer = computer.all_components[MC_PRINT]
		if(!card_slot)
			return

	var/mob/user = usr

	var/obj/item/card/id/modify = card_slot.stored_card
	var/obj/item/card/id/scan = card_slot.stored_card2

	switch(href_list["action"])
		if("PRG_modify")
			if(modify)
				GLOB.data_core.manifest_modify(modify.registered_name, modify.assignment)
				modify.name = "[modify.registered_name]'s ID Card ([modify.assignment])"
				card_slot.try_eject(1, user)
			else
				var/obj/item/I = usr.get_active_hand()
				if(istype(I, /obj/item/card/id))
					if(!usr.drop_item())
						return
					I.forceMove(computer)
					card_slot.stored_card = I

		if("PRG_scan")
			if(scan)
				card_slot.try_eject(2, user)
			else
				var/obj/item/I = usr.get_active_hand()
				if(istype(I, /obj/item/card/id))
					if(!usr.drop_item())
						return
					I.forceMove(computer)
					card_slot.stored_card2 = I

		if("PRG_access")
			if(href_list["allowed"])
				if(is_authenticated(usr))
					var/access_type = text2num(href_list["access_target"])
					var/access_allowed = text2num(href_list["allowed"])
					if(access_type in (is_centcom ? get_all_centcom_access() : get_all_accesses()))
						modify.access -= access_type
						if(!access_allowed)
							modify.access += access_type

		if("PRG_skin")
			var/skin = href_list["skin_target"]
			if(is_authenticated(usr) && modify && ((skin in get_station_card_skins()) || ((skin in get_centcom_card_skins()) && is_centcom)))
				modify.icon_state = href_list["skin_target"]

		if("PRG_assign")
			if(is_authenticated(usr) && modify)
				var/t1 = href_list["assign_target"]
				if(t1 == "Custom")
					var/temp_t = sanitize(copytext(input("Enter a custom job assignment.","Assignment"),1,MAX_MESSAGE_LEN))
					//let custom jobs function as an impromptu alt title, mainly for sechuds
					if(temp_t && modify)
						SSjobs.log_job_transfer(modify.registered_name, modify.getRankAndAssignment(), temp_t, scan.registered_name)
						modify.assignment = temp_t
						log_game("[key_name(usr)] has given \"[modify.registered_name]\" the custom job title \"[temp_t]\".")
				else
					var/list/access = list()
					if(is_centcom && islist(get_centcom_access(t1)))
						access = get_centcom_access(t1)
					else
						var/datum/job/jobdatum
						for(var/jobtype in typesof(/datum/job))
							var/datum/job/J = new jobtype
							if(ckey(J.title) == ckey(t1))
								jobdatum = J
								break
						if(!jobdatum)
							to_chat(usr, "<span class='warning'>No log exists for this job: [t1]</span>")
							return

						access = jobdatum.get_access()

					var/jobnamedata = modify.getRankAndAssignment()
					log_game("[key_name(usr)] has reassigned \"[modify.registered_name]\" from \"[jobnamedata]\" to \"[t1]\".")
					if(t1 == "Civilian")
						message_admins("[key_name_admin(usr)] has reassigned \"[modify.registered_name]\" from \"[jobnamedata]\" to \"[t1]\".")

					SSjobs.log_job_transfer(modify.registered_name, jobnamedata, t1, scan.registered_name)
					SSjobs.slot_job_transfer(modify.rank, t1)

					var/mob/living/carbon/human/H = modify.getPlayer()
					if(istype(H))
						if(jobban_isbanned(H, t1))
							message_admins("[ADMIN_FULLMONTY(H)] has been assigned the job [t1], in possible violation of their job ban.")
						if(H.mind)
							H.mind.playtime_role = t1

					modify.access = access
					modify.assignment = t1
					modify.rank = t1

		if("PRG_reg")
			if(is_authenticated(usr))
				var/temp_name = reject_bad_name(href_list["reg"])
				if(temp_name)
					modify.registered_name = temp_name
				else
					computer.visible_message("<span class='notice'>[src] buzzes rudely.</span>")

		if("PRG_account")
			if(is_authenticated(usr))
				var/account_num = text2num(href_list["account"])
				modify.associated_account_number = account_num

		if("PRG_mode")
			mode = text2num(href_list["mode_target"])

		if("PRG_wipe_my_logs")
			if(is_authenticated(usr) && is_centcom)
				var/delcount = SSjobs.delete_log_records(scan.registered_name, FALSE)
				if(delcount)
					playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 50, 0)

		if("PRG_wipe_all_logs")
			if(is_authenticated(usr))
				var/delcount = SSjobs.delete_log_records(scan.registered_name, TRUE)
				if(delcount)
					playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 50, 0)

		if("PRG_print")
			if(!printing && computer)
				printing = 1
				playsound(computer.loc, 'sound/goonstation/machines/printer_dotmatrix.ogg', 50, 1)
				spawn(50)
					printing = 0
					SSnanoui.update_uis(src)
					var/title
					var/content
					if(mode == 2)
						title = "crew manifest ([station_time_timestamp()])"
						content = "<h4>Crew Manifest</h4><br>[GLOB.data_core ? GLOB.data_core.get_manifest(0) : ""]"
					else if(modify && !mode)
						title = "access report"
						content = {"<h4>Access Report</h4>
							<u>Prepared By:</u> [scan && scan.registered_name ? scan.registered_name : "Unknown"]<br>
							<u>For:</u> [modify.registered_name ? modify.registered_name : "Unregistered"]<br>
							<hr>
							<u>Assignment:</u> [modify.assignment]<br>
							<u>Account Number:</u> #[modify.associated_account_number]<br>
							<u>Blood Type:</u> [modify.blood_type]<br><br>
							<u>Access:</u><div style="margin-left:1em">"}

						var/first = 1
						for(var/A in modify.access)
							content += "[first ? "" : ", "][get_access_desc(A)]"
							first = 0
						content += "</div>"

					if(content)
						if(!printer.print_text(content, title))
							to_chat(user, "<span class='notice'>Hardware error: Printer was unable to print the file. It may be out of paper.</span>")
							return 1
						else
							computer.visible_message("<span class='notice'>\The [computer] prints out paper.</span>")

		if("PRG_terminate")
			if(is_authenticated(usr))
				var/jobnamedata = modify.getRankAndAssignment()
				log_game("[key_name(usr)] has terminated the employment of \"[modify.registered_name]\" the \"[jobnamedata]\".")
				message_admins("[key_name_admin(usr)] has terminated the employment of \"[modify.registered_name]\" the \"[jobnamedata]\".")
				SSjobs.log_job_transfer(modify.registered_name, jobnamedata, "Terminated", scan.registered_name)
				modify.assignment = "Terminated"
				modify.access = list()

		if("PRG_make_job_available")
			// MAKE ANOTHER JOB POSITION AVAILABLE FOR LATE JOINERS
			if(is_authenticated(usr))
				var/edit_job_target = href_list["job"]
				var/datum/job/j = SSjobs.GetJob(edit_job_target)
				if(!j)
					return 1
				if(can_open_job(j) != 1)
					return 1
				if(opened_positions[edit_job_target] >= 0)
					GLOB.time_last_changed_position = world.time / 10
				j.total_positions++
				opened_positions[edit_job_target]++
				log_game("[key_name(usr)] has opened a job slot for job \"[j]\".")

		if("PRG_make_job_unavailable")
			// MAKE JOB POSITION UNAVAILABLE FOR LATE JOINERS
			if(is_authenticated(usr))
				var/edit_job_target = href_list["job"]
				var/datum/job/j = SSjobs.GetJob(edit_job_target)
				if(!j)
					return 1
				if(can_close_job(j) != 1)
					return 1
				//Allow instant closing without cooldown if a position has been opened before
				if(opened_positions[edit_job_target] <= 0)
					GLOB.time_last_changed_position = world.time / 10
				j.total_positions--
				opened_positions[edit_job_target]--
				log_game("[key_name(usr)] has closed a job slot for job \"[j]\".")


		if("PRG_prioritize_job")
			// TOGGLE WHETHER JOB APPEARS AS PRIORITIZED IN THE LOBBY
			if(is_authenticated(usr))
				var/priority_target = href_list["job"]
				var/datum/job/j = SSjobs.GetJob(priority_target)
				if(!j)
					return 0
				// Unlike the proper ID computer, this does not check job_in_department
				var/priority = TRUE
				if(j in SSjobs.prioritized_jobs)
					SSjobs.prioritized_jobs -= j
					priority = FALSE
				else if(SSjobs.prioritized_jobs.len < 3)
					SSjobs.prioritized_jobs += j
				else
					return 0
				log_game("[key_name(usr)] [priority ?  "prioritized" : "unprioritized"] the job \"[j.title]\".")
				playsound(computer.loc, 'sound/machines/terminal_prompt_confirm.ogg', 50, 0)

	if(modify)
		modify.name = text("[modify.registered_name]'s ID Card ([modify.assignment])")

	SSnanoui.update_uis(src)
	return 1

/datum/computer_file/program/card_mod/ui_data(mob/user)
	var/list/data = get_header_data()

	var/obj/item/card/id/modify = null
	var/obj/item/card/id/scan = null

	var/obj/item/computer_hardware/card_slot/card_slot
	var/obj/item/computer_hardware/printer/printer
	if(computer)
		card_slot = computer.all_components[MC_CARD]
		printer = computer.all_components[MC_PRINT]
		if(card_slot)
			modify = card_slot.stored_card
			scan = card_slot.stored_card2

	data["src"] = UID()
	data["station_name"] = station_name()
	data["mode"] = mode
	data["printing"] = printing
	data["printer"] = printer ? TRUE : FALSE
	data["manifest"] = GLOB.data_core ? GLOB.data_core.get_manifest(0) : null
	data["target_name"] = modify ? modify.name : "-----"
	data["target_owner"] = modify && modify.registered_name ? modify.registered_name : "-----"
	data["target_rank"] = get_target_rank()
	data["scan_name"] = scan ? scan.name : "-----"
	data["scan_owner"] = scan && scan.registered_name ? scan.registered_name : null
	data["authenticated"] = is_authenticated(user)
	data["has_modify"] = !!modify
	data["account_number"] = modify ? modify.associated_account_number : null
	data["centcom_access"] = is_centcom
	data["all_centcom_access"] = null
	data["regions"] = null

	var/list/job_formats = SSjobs.format_jobs_for_id_computer(modify)

	data["top_jobs"] = format_jobs(list("Captain", "Custom"), data["target_rank"], job_formats)
	data["engineering_jobs"] = format_jobs(GLOB.engineering_positions, data["target_rank"], job_formats)
	data["medical_jobs"] = format_jobs(GLOB.medical_positions, data["target_rank"], job_formats)
	data["science_jobs"] = format_jobs(GLOB.science_positions, data["target_rank"], job_formats)
	data["security_jobs"] = format_jobs(GLOB.security_positions, data["target_rank"], job_formats)
	data["support_jobs"] = format_jobs(GLOB.support_positions, data["target_rank"], job_formats)
	data["civilian_jobs"] = format_jobs(GLOB.civilian_positions, data["target_rank"], job_formats)
	data["special_jobs"] = format_jobs(GLOB.whitelisted_positions, data["target_rank"], job_formats)
	data["centcom_jobs"] = format_jobs(get_all_centcom_jobs(), data["target_rank"], job_formats)
	data["card_skins"] = format_card_skins(get_station_card_skins())

	data["job_slots"] = format_job_slots()

	var/time_to_wait = round(change_position_cooldown - ((world.time / 10) - GLOB.time_last_changed_position), 1)
	var/mins = round(time_to_wait / 60)
	var/seconds = time_to_wait - (60*mins)
	data["cooldown_mins"] = mins
	data["cooldown_secs"] = (seconds < 10) ? "0[seconds]" : seconds

	if(mode == 3 && is_authenticated(user))
		data["id_change_html"] = SSjobs.fetch_transfer_record_html(is_centcom)

	if(modify)
		data["current_skin"] = modify.icon_state

	if(modify && is_centcom)
		var/list/all_centcom_access = list()
		for(var/access in get_all_centcom_access())
			all_centcom_access.Add(list(list(
				"desc" = replacetext(get_centcom_access_desc(access), " ", "&nbsp;"),
				"ref" = access,
				"allowed" = (access in modify.access) ? 1 : 0)))

		data["all_centcom_access"] = all_centcom_access
		data["all_centcom_skins"] = format_card_skins(get_centcom_card_skins())

	else if(modify)
		var/list/regions = list()
		for(var/i = 1; i <= 7; i++)
			var/list/accesses = list()
			for(var/access in get_region_accesses(i))
				if(get_access_desc(access))
					accesses.Add(list(list(
						"desc" = replacetext(get_access_desc(access), " ", "&nbsp;"),
						"ref" = access,
						"allowed" = (access in modify.access) ? 1 : 0)))

			regions.Add(list(list(
				"name" = get_region_accesses_name(i),
				"accesses" = accesses)))

		data["regions"] = regions

	return data
