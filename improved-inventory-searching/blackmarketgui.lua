local rows = tweak_data.gui.WEAPON_ROWS_PER_PAGE
local columns = tweak_data.gui.WEAPON_COLUMNS_PER_PAGE

Hooks:PreHook(BlackMarketGui, "init", "InventorySearch", function (self, ws, fullscreen_ws, node)
	local data = node:parameters().menu_component_data
	
	if not data then return end

	if (data.category == "primaries") or (data.category == "secondaries") or (data.category == "masks") then
		data.search_box_disconnect_callback_name = "_InventorySearch_on_search_item"

		if data.search_string then
			self._saved_search = data.search_string
		end
	end
end)

Hooks:PostHook(BlackMarketGui, "init", "InventorySearch", function (self)
	if self._searchbox then
		local keyboard = Input:keyboard()
		self._InventorySearch_s_trigger = keyboard:add_trigger(keyboard:button_index(Idstring("s")), function ()
			if not self._renaming_item then
				self._searchbox:connect_search_input()
			end
		end)
	end
end)

Hooks:PostHook(BlackMarketGui, "close", "InventorySearch", function (self)
	if self._InventorySearch_s_trigger then
		Input:keyboard():remove_trigger(self._InventorySearch_s_trigger)
		self._InventorySearch_s_trigger = nil
	end
end)

function BlackMarketGui:_InventorySearch_on_search_item(search_string)
	if search_string ~= "" then
		if not self._data.InventorySearch_original_data then
			-- self._data is the original data! Remember which tab is selected.
			self._data.selected_tab = self._selected
		end

		-- Force the first slot to be selected when searching.
		local tabs = self._node:parameters().menu_component_tabs
		tabs.InventorySearch_1 = tabs.InventorySearch_1 or {}
		tabs.InventorySearch_1.selected = 1

		-- This may refer to a tab that doesn't exist, so it must be reset or else it may cause a crash!
		self._highlighted = nil -- Crisis averted.

		managers.blackmarket:drop_hold_crafted_item()
		self:_InventorySearch_prepare_data(search_string)
	elseif self._data.InventorySearch_original_data then
		self._data = self._data.InventorySearch_original_data
	end

	self:on_search_item(search_string)
end

function BlackMarketGui:_InventorySearch_prepare_data(search_string)
	if self._data.InventorySearch_original_data then return end

	local on_create_func_name = nil

	if (self._data.category == "primaries") or (self._data.category == "secondaries") then
		on_create_func_name = "_InventorySearch_prepare_weapons_tab"
	elseif self._data.category == "masks" then
		on_create_func_name = "_InventorySearch_prepare_masks_tab"
	end

	self._data = {
		InventorySearch_original_data = self._data,
		category = self._data.category,
		topic_id = self._data.topic_id,
		search_box_disconnect_callback_name = "_InventorySearch_on_search_item",
		search_string = search_string,
		selected_tab = 1,
		{
			name = "InventorySearch_1",
			name_localized = managers.localization:to_upper_text("bm_menu_page", {
				page = "1"
			}),
			identifier = self._data[1].identifier,
			category = self._data.category,
			on_create_func_name = on_create_func_name,
			allow_preview = self._data[1].allow_preview,
			override_slots = {
				rows,
				columns
			}
		}
	}
end

function BlackMarketGui:_InventorySearch_split_search_string(search_string)
	search_string = utf8.to_lower(search_string)
	local start = search_string:find(":", 1, true)
	local prefix = nil

	if start then
		prefix = search_string:sub(1, start - 1)
		search_string = search_string:sub(start + 1)
	end

	return prefix, search_string
end

function BlackMarketGui:_InventorySearch_fill_empty_slots(tab, slots_occupied)
	local slots_empty = nil
	local min_slots = rows * columns

	if slots_occupied > min_slots then
		local max_rows = math.ceil(slots_occupied / columns)
		slots_empty = (max_rows * columns) - slots_occupied
	else
		slots_empty = min_slots - slots_occupied
	end

	for i = 1, slots_empty do
		tab[#tab + 1] = {
			name = "empty",
			category = tab.category,
			not_moddable = true -- Prevents renaming.
		}
	end
end

-- Weapons

function BlackMarketGui:_InventorySearch_prepare_weapons_tab(tab)
	for i in ipairs(tab) do
		tab[i] = nil
	end

	local weapons = managers.blackmarket:get_crafted_category(tab.category)
	local weapon_indices, weapon_names = self:_InventorySearch_get_weapon_search_results(self._data.search_string, tab.category, weapons)
	local has_last_weapon, has_last_unlocked_weapon = self:_InventorySearch_check_weapon_count(weapons)

	for i, index in ipairs(weapon_indices) do
		self:_InventorySearch_prepare_weapon_slot(tab, weapons[index], index, weapon_names[index], has_last_weapon, has_last_unlocked_weapon)
	end

	self:_InventorySearch_fill_empty_slots(tab, #weapon_indices)
end

function BlackMarketGui:_InventorySearch_get_weapon_search_results(search_string, category, weapons)
	local prefix, search_string = self:_InventorySearch_split_search_string(search_string)
	local weapon_indices = {}
	local weapon_names = {}

	for i, weapon in pairs(weapons) do
		local str = nil
		local name = managers.blackmarket:get_weapon_name_by_category_slot(category, i)

		if prefix == "m" then
			str = managers.weapon_factory:get_weapon_name_by_factory_id(weapon.factory_id)
		elseif prefix == "c" then
			local category_name = self:_InventorySearch_get_weapon_category_name(category, weapon.weapon_id)
			assert(category_name)
			str = category_name
		elseif prefix == "i" then
			str = weapon.weapon_id
		elseif prefix == "d" then
			local global_value = tweak_data.weapon[weapon.weapon_id].global_value or "normal"
			local global_value_desc_id = tweak_data.lootdrop.global_values[global_value].desc_id
			str = managers.localization:text(global_value_desc_id)
		else
			str = name
		end	

		str = utf8.to_lower(str)

		if str:find(search_string, 1, true) then
			weapon_indices[#weapon_indices + 1] = i
			weapon_names[i] = name
		end
	end

	table.sort(weapon_indices, function (a, b)
		return weapon_names[a] < weapon_names[b]
	end)

	return weapon_indices, weapon_names
end

function BlackMarketGui:_InventorySearch_get_weapon_category_name(selection_category, weapon_id)
	local function get_category_id(categories, category_aliases, weapon_categories)
		for i, category in ipairs(categories) do
			local weapon_category = weapon_categories[i]

			if category ~= (category_aliases[weapon_category] or weapon_category) then
				return nil
			end
		end

		return table.concat(categories, "_")
	end

	local gui_categories = tweak_data.gui.buy_weapon_categories[selection_category]
	local category_aliases = tweak_data.gui.buy_weapon_category_aliases
	local weapon_categories = tweak_data.weapon[weapon_id].categories

	for i, categories in ipairs(gui_categories) do
		local id = get_category_id(categories, category_aliases, weapon_categories)

		if id then
			return managers.localization:text("menu_" .. id)
		end
	end

	return nil
end

function BlackMarketGui:_InventorySearch_check_weapon_count(weapons)
	local weapon_count = 0
	local unlocked_weapon_count = 0

	for i, weapon in pairs(weapons) do
		weapon_count = weapon_count + 1

		if managers.blackmarket:weapon_unlocked(weapon.weapon_id) then
			unlocked_weapon_count = unlocked_weapon_count + 1

			if unlocked_weapon_count > 1 then break end
		end
	end

	return (weapon_count == 1), (unlocked_weapon_count == 1)
end

function BlackMarketGui:_InventorySearch_prepare_weapon_slot(tab, weapon, weapon_index, weapon_name, has_last_weapon, has_last_unlocked_weapon)
	local unlocked, part_dlc_lock = managers.blackmarket:weapon_unlocked_by_crafted(tab.category, weapon_index)
	local global_value = tweak_data.weapon[weapon.weapon_id].global_value or "normal"
	local locked_global_value_tweak = tweak_data.lootdrop.global_values[part_dlc_lock or global_value]
	local last_weapon = has_last_weapon or (has_last_unlocked_weapon and unlocked)
	local bitmap_texture, bg_texture = managers.blackmarket:get_weapon_icon_path(weapon.weapon_id, weapon.cosmetics)
	local new_part_types, new_drop_data = self:_InventorySearch_check_new_parts(weapon.factory_id)
	local global_weapon_data = Global.blackmarket_manager.weapons[weapon.weapon_id]
	local name_color = nil

	if weapon.locked_name and weapon.cosmetics then
		local rarity = tweak_data.blackmarket.weapon_skins[weapon.cosmetics.id].rarity or "common"
		name_color = tweak_data.economy.rarities[rarity].color
	end

	local vr_locked = nil

	if _G.IS_VR then
		vr_locked = tweak_data.vr:is_locked("weapons", weapon.weapon_id)
		unlocked = unlocked and not vr_locked
	end

	local data = {
		name = weapon.weapon_id,
		name_localized = weapon_name,
		raw_name_localized = managers.weapon_factory:get_weapon_name_by_factory_id(weapon.factory_id),
		custom_name_text = managers.blackmarket:get_crafted_custom_name(tab.category, weapon_index, true),
		category = tab.category,
		slot = weapon_index,
		level = managers.blackmarket:weapon_level(weapon.weapon_id),
		price = managers.money:get_weapon_slot_sell_value(tab.category, weapon_index),
		can_afford = true,
		vr_locked = vr_locked,
		unlocked = unlocked,
		part_dlc_lock = part_dlc_lock,
		dlc_locked = (locked_global_value_tweak and locked_global_value_tweak.unlock_id) or part_dlc_lock or nil,
		costomize_locked = weapon.customize_locked,
		locked_name = weapon.locked_name,
		name_color = name_color,
		equipped = weapon.equipped,
		last_weapon = last_weapon,
		bitmap_texture = bitmap_texture,
		bg_texture = bg_texture,
		bitmap_color = Color.white,
		stream = true,
		comparision_data = managers.blackmarket:get_weapon_stats(tab.category, weapon_index),
		global_value = global_value,
		hide_unselected_mini_icons = true,
		mini_icons = self:_InventorySearch_get_weapon_mini_icons(tab.category, weapon_index, weapon, new_part_types),
		new_drop_data = new_drop_data,
		skill_based = global_weapon_data.skill_based,
		skill_name = global_weapon_data.skill_based and "bm_menu_skill_locked_" .. weapon.weapon_id,
		func_based = global_weapon_data.func_based
	}
	data.lock_texture = self:get_lock_icon(data)
	
	-- Buttons begin.
	if managers.weapon_factory:has_weapon_more_than_default_parts(weapon.factory_id) then
		data[#data + 1] = "w_mod"
	end

	if not last_weapon then
		data[#data + 1] = "w_sell"
	end

	if not data.equipped and unlocked then
		data[#data + 1] = "w_equip"
	end

	if tab.allow_preview then
		data[#data + 1] = "w_preview"
	end
	-- Buttons end.

	tab[#tab + 1] = data
end

function BlackMarketGui:_InventorySearch_check_new_parts(factory_id)
	local new_parts = managers.blackmarket:get_weapon_new_part_drops(factory_id)
	local new_part_types = {}
	local parts_tweak = tweak_data.weapon.factory.parts

	for i, part in ipairs(new_parts) do
		local type = parts_tweak[part].type
		new_part_types[type] = true
	end

	local new_drop_data = nil

	if new_parts[1] then
		new_drop_data = {}
	end

	return new_part_types, new_drop_data
end

function BlackMarketGui:_InventorySearch_get_weapon_mini_icons(category, weapon_index, weapon, new_part_types)
	local mini_icons = {}
	local icon_list = managers.menu_component:create_weapon_mod_icon_list(weapon.weapon_id, category, weapon.factory_id, weapon_index)
	local icon_index = 1

	for i, icon in ipairs(icon_list) do
		local right = (icon_index - 1) % 11 * 18
		local bottom = math.floor((icon_index - 1) / 11) * 25

		mini_icons[#mini_icons + 1] = {
			texture = icon.texture,
			stream = false,
			layer = 1,
			color = Color.white,
			alpha = icon.equipped and 1 or 0.25,
			w = 16,
			h = 16,
			right = right,
			bottom = bottom
		}

		if new_part_types[icon.type] then
			mini_icons[#mini_icons + 1] = {
				texture = "guis/textures/pd2/blackmarket/inv_mod_new",
				stream = false,
				layer = 1,
				color = Color.white,
				alpha = 1,
				w = 16,
				h = 8,
				right = right,
				bottom = bottom + 16
			}
		end

		icon_index = icon_index + 1
	end

	local color_tweak = weapon.cosmetics and tweak_data.blackmarket.weapon_skins[weapon.cosmetics.id]

	if color_tweak and color_tweak.is_a_color_skin then
		local guis_folder = "guis/"
		local bundle_folder = color_tweak.texture_bundle_folder

		if bundle_folder then
			guis_folder = guis_folder .. "dlcs/" .. bundle_folder
		end

		mini_icons[#mini_icons + 1] = {
			texture = guis_folder .. "textures/pd2/blackmarket/icons/weapon_color/" .. weapon.cosmetics.id,
			stream = true,
			layer = 0,
			w = 64,
			h = 32,
			right = -16,
			bottom = math.floor((#icon_list - 1) / 11) * 25 + 24
		}
	end

	return mini_icons
end

-- Masks

local is_win32 = SystemInfo:platform() == Idstring("WIN32")
local grid_h_mul = (is_win32 and 6.95 or 6.9) / 8
local items_per_column = 3
local mask_part_map = {
	pattern = "textures",
	color = "colors",
	material = "materials"
}

function BlackMarketGui:_InventorySearch_prepare_masks_tab(tab)
	for i in ipairs(tab) do
		tab[i] = nil
	end

	local masks = managers.blackmarket:get_crafted_category("masks")
	local mask_indices, mask_names = self:_InventorySearch_get_mask_search_results(self._data.search_string, masks)

	for i, index in ipairs(mask_indices) do
		self:_InventorySearch_prepare_mask_slot(tab, masks[index], index, mask_names[index])
	end

	self:_InventorySearch_fill_empty_slots(tab, #mask_indices)
end

function BlackMarketGui:_InventorySearch_get_mask_search_results(search_string, masks)
	local prefix, search_string = self:_InventorySearch_split_search_string(search_string)
	local mask_indices = {}
	local mask_names = {}

	for i, mask in pairs(masks) do
		local str = nil
		local name = managers.blackmarket:get_mask_name_by_category_slot("masks", i)

		if prefix == "m" then
			str = managers.localization:text(tweak_data.blackmarket.masks[mask.mask_id].name_id)
		elseif prefix == "c" then
			local category_id = "bm_menu_" .. tweak_data.lootdrop.global_values[mask.global_value].category
			str = managers.localization:text(category_id)
		elseif prefix == "i" then
			str = mask.mask_id
		elseif prefix == "d" then
			local global_value_desc_id = tweak_data.lootdrop.global_values[mask.global_value].desc_id
			str = managers.localization:text(global_value_desc_id)
		else
			str = name
		end

		str = utf8.to_lower(str)

		if str:find(search_string, 1, true) then
			mask_indices[#mask_indices + 1] = i
			mask_names[i] = name
		end
	end

	return mask_indices, mask_names
end

function BlackMarketGui:_InventorySearch_prepare_mask_slot(tab, mask, mask_index, mask_name)
	local masks_tweak = tweak_data.blackmarket.masks
	local guis_mask_id = masks_tweak[mask.mask_id].guis_id or mask.mask_id
	local data = {
		name = mask.mask_id,
		name_localized = managers.blackmarket:get_mask_name_by_category_slot("masks", mask_index),
		raw_name_localized = managers.localization:text(tweak_data.blackmarket.masks[mask.mask_id].name_id),
		custom_name_text = managers.blackmarket:get_crafted_custom_name("masks", mask_index, true),
		custom_name_text_right = mask.modded and -55 or -20,
		custom_name_text_width = mask.modded and 0.6,
		category = "masks",
		global_value = mask.global_value,
		slot = mask_index,
		unlocked = true,
		equipped = mask.equipped,
		bitmap_texture = managers.blackmarket:get_mask_icon(guis_mask_id, self._data.character_id),
		bitmap_color = Color.white,
		stream = false,
		item_id = mask.item_id
	}
	local dlc = masks_tweak[mask.mask_id].dlc or managers.dlc:global_value_to_dlc(mask.global_value)

	if dlc and not managers.dlc:is_dlc_unlocked(dlc) then
		data.unlocked = false
		data.lock_texture = self:get_lock_icon(data, "guis/textures/pd2/lock_incompatible")
		local mask_global_value_tweak = tweak_data.lootdrops.global_values[mask.global_value]
		data.dlc_locked = mask_global_value_tweak and mask_global_value_tweak.unlock_id or "bm_menu_dlc_locked"
	elseif not managers.dlc:is_content_achievement_locked("masks", mask.mask_id)
		and not managers.dlc:is_content_achievement_milestone_locked("masks", mask.mask_id)
		and not managers.dlc:is_content_skirmish_locked("masks", mask.mask_id)
		and not managers.dlc:is_content_crimespree_locked("masks", mask.mask_id)
		and not managers.dlc:is_content_infamy_locked("masks", mask.mask_id) then
		
		local challenge = managers.event_jobs:get_challenge_from_reward("masks", mask.mask_id)

		if challenge and not challenge.completed then
			data.unlocked = false
			data.lock_texture = "guis/textures/pd2/lock_achievement"
			data.dlc_locked = challenge.locked_id or "menu_event_job_lock_info"
		end
	end

	local locked_part_global_values = {}

	if data.unlocked then
		local default_blueprint = tweak_data.blackmarket.masks[mask.mask_id].default_blueprint or {}

		for kind, part in pairs(mask.blueprint) do
			if (default_blueprint[kind] ~= part.id) and (default_blueprint[mask_part_map[kind]] ~= part.id) then
				local part_global_value_tweak = tweak_data.lootdrop.global_values[part.global_value]

				if part_global_value_tweak and part_global_value_tweak.dlc and not managers.dlc:is_dlc_unlocked(part.global_value) then
					locked_part_global_values[kind] = part.global_value
					data.lock_texture = self:get_lock_icon(data, "guis/textures/pd2/lock_incompatible")
					data.dlc_locked = part_global_value_tweak.unlock_id or "bm_menu_dlc_locked"
					break
				end
			end
		end
	end

	data.mini_icons, data.new_drop_data = self:_InventorySearch_get_mask_mini_icons(mask, mask_index, locked_part_global_values)

	-- Buttons begin.
	if data.unlocked and not data.equipped then
		data[#data + 1] = "m_equip"
	end

	if mask_index ~= 1 then
		if data.unlocked and not mask.modded and managers.blackmarket:can_modify_mask(mask_index) then
			data[#data + 1] = "m_mod"
		end

		if managers.money:get_mask_sell_value(mask.mask_id, mask.global_value) > 0 then
			data[#data + 1] = "m_sell"
		else
			data[#data + 1] = "m_remove"
		end
	end

	data[#data + 1] = "m_preview"
	-- Buttons end.

	tab[#tab + 1] = data
end

function BlackMarketGui:_InventorySearch_get_mask_mini_icons(mask, mask_index, locked_part_global_values)
	local mini_icons = nil
	local new_drop_data = nil

	if mask.modded then
		local mask_colors_tweak = tweak_data.blackmarket.mask_colors
		mini_icons = {
			borders = true,
			{
				texture = false,
				color = mask_colors_tweak[mask.blueprint.color_b.id].color,
				layer = 1,
				right = 0,
				bottom = 0,
				w = 16,
				h = 16
			},
			{
				texture = false,
				color = mask_colors_tweak[mask.blueprint.color_a.id].color,
				layer = 1,
				right = 18,
				bottom = 0,
				w = 16,
				h = 16
			}
		}

		if locked_part_global_values.color then
			local texture = self:get_lock_icon({
				global_value = locked_part_global_values.color
			})
			mini_icons[#mini_icons + 1] = {
				texture = texture,
				color = tweak_data.screen_colors.important_1,
				layer = 2,
				right = 6,
				bottom = -4,
				w = 24,
				h = 24
			}
		end

		local pattern_id = mask.blueprint.pattern.id

		if (pattern_id ~= "solidfirst") and (pattern_id ~= "solidsecond") then
			local guis_folder = "guis/"
			local material_id = mask.blueprint.material.id
			local material_tweak = tweak_data.blackmarket.materials[material_id]
			local bundle_folder = material_tweak and material_tweak.texture_bundle_folder

			if bundle_folder then
				guis_folder = guis_folder .. "dlcs/" .. bundle_folder .. "/"
			end

			local right = 2
			local bottom = 28
			local w = 32
			local h = 32
			
			mini_icons[#mini_icons + 1] = {
				texture = guis_folder .. "textures/pd2/blackmarket/icons/materials/" .. material_id,
				stream = true,
				layer = 1,
				right = right,
				bottom = bottom,
				w = w,
				h = h
			}

			if locked_part_global_values.material then
				local texture = self:get_lock_icon({
					global_value = locked_part_global_values.material
				})
				mini_icons[#mini_icons + 1] = {
					texture = texture,
					color = tweak_data.screen_colors.important_1,
					layer = 2,
					right = right + 4,
					bottom = bottom + 4,
					w = w - 8,
					h = w - 8
				}
			end
		end

		local mini_icon_helper = math.round((self._panel:h() - (tweak_data.menu.pd2_small_font_size + 10) - 60) * grid_h_mul / items_per_column) - 16
		local right = 2
		local bottom = math.round(mini_icon_helper - 84)
		local w = 32
		local h = 32

		mini_icons[#mini_icons + 1] = {
			texture = tweak_data.blackmarket.textures[pattern_id].texture,
			render_template = Idstring("VertexColorTexturedPatterns"),
			stream = true,
			layer = 1,
			right = right,
			bottom = bottom,
			w = w,
			h = h
		}

		if locked_part_global_values.pattern then
			local texture = self:get_lock_icon({
				global_value = locked_part_global_values.pattern
			})
			mini_icons[#mini_icons + 1] = {
				texture = texture,
				color = tweak_data.screen_colors.important_1,
				layer = 2,
				right = right + 4,
				bottom = bottom + 4,
				w = w - 8,
				h = w - 8
			}
		end
	elseif (mask_index ~= 1) and managers.blackmarket:can_modify_mask(mask_index) and managers.blackmarket:got_new_drop("normal", "mask_mods", mask.mask_id) then
		mini_icons = {
			{
				name = "new_drop",
				texture = "guis/textures/pd2/blackmarket/inv_newdrop",
				stream = false,
				layer = 1,
				right = 0,
				top = 0,
				w = 16,
				h = 16,
				visible = true
			}
		}
		new_drop_data = {}
	end

	return mini_icons, new_drop_data
end
