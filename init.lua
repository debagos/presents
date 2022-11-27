--[[
	Shout out to @rubenwardy, ContentDB is awesome!
	And a big thank you to everyone who is involved in Minetest in general.
	Lastly a big thank you to my awesome WunderWelt community, I love you all!
]]--

local mod_name = minetest.get_current_modname()
local S = minetest.get_translator(mod_name)
local string_sub = string.sub

local colors = {
	{ "Black", "#000000"},
	{ "White", "#aaaaaa"},
	{ "Red", "#aa0000"},
	{ "Green", "#00aa00"},
	{ "Blue", "#0000aa"},
	{ "Yellow", "#aaaa00"},
	{ "Orange", "#ffa500"},
	{ "Pink", "#ff4d6a"},
	{ "Cyan", "#00ffff"},
	{ "Brown", "#433232"},
	{ "Gray", "#808080"} -- *sigh*
}

local node_timer_interval = 60

local node_glow = 6
local entity_glow = 1
--[[
	If you tweak one of this values, you have to tweak the other one as well, to make sure that the node color and entitiy color match.
	Possible values: a number between 0 and 14 ('minetest.LIGHT_MAX')
]]--

local entity_log_level = "warning"
--[[
	default: "warning"
	There are some non-critical errors that can happen, for example if someone moves a present with a Mesecons piston.
	With 'entity_log_level' you can change what log level will be used to report those non-critial issues.
	On high pop servers it could make sense to set this to "info" to keep the logs clean.
	Possible values: "none", "error", "warning", "action", "info", or "verbose".
]]--

local has_mod_default = false
local has_mod_dye = false
--[[
	Don't modify these.
	The presence of the mods 'default' and 'dye' will get checked automatically later in this script.
]]--

local has_unified_inventory = false
--[[
	Don't modify this.
	The mod will check if 'unified_inventory' is installed and active and if there is already a crafting recipe registered with the same ingredients a present would require.
	If that's the case, you will get a warning.
	When two crafting recipes have the same input ingredients, you can't choose in 'unified_inventory' what output you will craft/get. That would lead to uncraftable items, hence the need for a warning.
]]--

local min_particles_per_interval = 1
local max_particles_per_interval = 10
--[[
	default min: 1
	default max: 10
	This is the minimum and maximum range of particles that possibly can spawn over a 'node_timer_interval' interval.
	If you set these values too high, players with low-end devices will get after you, because their FPS will drop significantly!
]]--

local paper_item_string = "default:paper"

local random_generator = PcgRandom(os.time() + (math.random() * 1000))

--[[ ## Ribbon entities ## ]]--

local function present_is_present(pos) -- lol
	local node = minetest.get_node(pos)
	if node.name == "ignore" then
		minetest.load_area(pos)
		node = minetest.get_node(pos)
	end
	return string_sub(node.name, 1, #(mod_name..":")) == mod_name..":"
end

local function register_ribbon(color_name_lowercase, color_value)
	minetest.register_entity(mod_name..":ribbon_"..color_name_lowercase, {
		initial_properties = {
			visual = "sprite",
			visual_size = { x = 0.4, y = 0.4, z = 0.4 },
			collisionbox = { },
			physical = false,
			pointable = false,
			textures = { "presents_ribbon.png^[multiply:"..color_value },
			use_texture_alpha = true,
			glow = entity_glow,
			show_on_minimap = false, -- could be cool to make them visible on the minimap maybe
			groups = { immortal = 1, punch_operable = 1 },
			static_save = true
		},
		on_activate = function(self, staticdata, dtime_s)
			local pos = self.object:get_pos()
			if pos ~= nil then
				if not present_is_present(pos) then
					minetest.log(entity_log_level, "["..mod_name.."] Present below ribbon at "..minetest.pos_to_string(pos, 0).." is gone. Removing ribbon.")
					self.object:remove()
				end
			end
		end
	})
end

for _, set in pairs(colors) do
	register_ribbon(string.lower(set[1]), set[2])
end

--[[ ## Ribbon functions ## ]]--

local function add_ribbon(pos, color)
	local ribbon_pos = { x = pos.x, y = pos.y + 0.2, z = pos.z }
	local ribbon_name = mod_name..":ribbon_"..color
	local object_ref = minetest.add_entity(ribbon_pos, ribbon_name)
	if object_ref == nil then
		minetest.log("error", "["..mod_name.."] Failed to add ribbon '"..ribbon_name.."' to present at position "..minetest.pos_to_string(pos, 0))
	end
	local node_timer = minetest.get_node_timer(pos)
	if node_timer == nil then
		minetest.log("error", "["..mod_name.."] Failed to get node timer at position "..minetest.pos_to_string(pos, 0)..". Can't enable ribbon check there...")
	else
		if not node_timer:is_started() then
			node_timer:start(node_timer_interval)
		end
	end
end

local function remove_ribbon(pos, color)
	local ribbon_name = mod_name..":ribbon_"..color
	local found_ribbon = false
	for _, object_ref in pairs(minetest.get_objects_inside_radius(pos, 0.6)) do
		if object_ref ~= nil then
			local lua_entity = object_ref:get_luaentity()
			if lua_entity ~= nil then
				if lua_entity.name == ribbon_name then
					object_ref:remove()
					found_ribbon = true
					--break
					--[[
						don't break here because there might be more than one ribbon:
							node timer got executed while the entities have not been loaded yet, which makes the node timer create a new one
					]]--
				end
			end
		end
	end
	if not found_ribbon then
		minetest.log(entity_log_level, "["..mod_name.."] Failed to remove ribbon '"..ribbon_name.."' from present at position "..minetest.pos_to_string(pos, 0))
	end
end

local function check_ribbon(pos, color)
	local ribbon_name = mod_name..":ribbon_"..color
	local ribbons_found = 0
	for _, object_ref in pairs(minetest.get_objects_inside_radius(pos, 0.6)) do
		if object_ref ~= nil then
			local lua_entity = object_ref:get_luaentity()
			if lua_entity ~= nil then
				if lua_entity.name == ribbon_name then
					ribbons_found = ribbons_found + 1
				end
			end
		end
	end
	if ribbons_found == 0 then
		minetest.log(entity_log_level, "["..mod_name.."] Ribbon above present at "..minetest.pos_to_string(pos, 0).." is gone. Adding a new ribbon.")
		add_ribbon(pos, color)
	elseif ribbons_found > 1 then
		minetest.log(entity_log_level, "["..mod_name.."] Found "..tostring(ribbons_found).." ribbons above present at "..minetest.pos_to_string(pos, 0)..". Removing them all and creating one new.")
		remove_ribbon(pos, color)
		add_ribbon(pos, color)
	end
end

local function get_random_vector(high_values)
	local vector = { }
	local random_x, random_y, random_z
	if high_values then
		random_x = random_generator:next(1, 100) / 100
		random_y = random_generator:next(10, 100) / 100
		random_z = random_generator:next(1, 100) / 100
	else
		random_x = random_generator:next(1, 25) / 100
		random_y = random_generator:next(10, 25) / 100
		random_z = random_generator:next(1, 25) / 100
	end
	vector.x = (random_generator:next(1, 2) == 1 and random_x) or -random_x
	vector.y = random_y
	vector.z = (random_generator:next(1, 2) == 1 and random_z) or -random_z
	return vector
end

local function spawn_particle(pos, color_base, color_overlay)
	if present_is_present(pos) then
		local particle_color = (random_generator:next(1, 2) == 1 and color_base) or color_overlay
		minetest.add_particle({
			pos = { x = pos.x, y = pos.y + 0.1 , z = pos.z },
			velocity = get_random_vector(true),
			acceleration = get_random_vector(false),
			expirationtime = random_generator:next(2, 5),
			size = random_generator:next(40, 75) / 100,
			collisiondetection = true,
			collision_removal = true,
			object_collision = true,
			glow = entity_glow,
			texture = "presents_particle.png^[multiply:"..particle_color,
		})
	end
end

--[[ ## Presents ## ]]--

local function register_present(color_base_name, color_base_value)
	local color_base_name_lowercase = string.lower(color_base_name)
	for _, set in pairs(colors) do
		local color_overlay_name = set[1]
		local color_overlay_name_lowercase = string.lower(color_overlay_name)
		local color_overlay_value = set[2]
		if color_base_name_lowercase ~= color_overlay_name_lowercase then -- we skip presents where the strip would be the same color as the casing
			minetest.register_node(mod_name..":"..color_base_name_lowercase.."_"..color_overlay_name_lowercase, {
				description = S("Present").." ("..S(color_base_name).."-"..S(color_overlay_name)..")",
				use_texture_alpha = "opaque",
				-- order: top, bottom, side1, side2, back, front
				tiles = {
					{ name = "presents_top.png", color = color_base_value },
					{ name = "presents_top.png", color = color_base_value },
					{ name = "presents_side.png", color = color_base_value },
					{ name = "presents_side.png", color = color_base_value },
					{ name = "presents_side.png", color = color_base_value },
					{ name = "presents_side.png", color = color_base_value },
				},
				overlay_tiles = {
					{ name = "presents_top_overlay.png", color = color_overlay_value },
					{ name = "presents_top_overlay.png", color = color_overlay_value },
					{ name = "presents_side_overlay.png", color = color_overlay_value },
					{ name = "presents_side_overlay.png", color = color_overlay_value },
					{ name = "presents_side_overlay.png", color = color_overlay_value },
					{ name = "presents_side_overlay.png", color = color_overlay_value },
				},
				drawtype = "nodebox",
				node_box = {
					type = "fixed",
					fixed = {
						-- { x1, y1, z1, x2, y2, z2 }
						{ -0.35, -0.5, -0.35, 0.35, 0, 0.35 }
					}
				},
				paramtype = "light",
				sunlight_propagates = true,
				light_source = node_glow,
				floodable = false,
				buildable_to = false,
				is_ground_content = false,
				drowning = 0,
				damage_per_second = 0,
				groups = {
					attached_node = 1, -- when the node below it is removed, the present will drop as an item
					bouncy = 80, -- bounce speed in percent, this makes the present basically a trampoline
					dig_immediate = 2, -- node is dug after 0.5 seconds, without reducing tool wear
					fall_damage_add_percent = -100 -- you will never receive damage when landing on a present, no matter how far the fall is
				},
				sounds = {
					footstep = "presents_footstep",
					dig = "presents_dig",
					dug = "presents_dug",
					place = "presents_place",
				},
				on_blast = function(pos, intensity) end, -- makes the present immune to TNT and all other kinds of explosions
				on_construct = function(pos)
					add_ribbon(pos, color_overlay_name_lowercase)
					local particle_amount = random_generator:next(min_particles_per_interval, max_particles_per_interval)
					if particle_amount > 0 then
						for particle_counter = 1, particle_amount do
							local random_timeout = random_generator:next(0, node_timer_interval)
							minetest.after(random_timeout, spawn_particle, pos, color_base_value, color_overlay_value)
						end
					end
				end,
				on_timer = function(pos)
					check_ribbon(pos, color_overlay_name_lowercase)
					local particle_amount = random_generator:next(min_particles_per_interval, max_particles_per_interval)
					if particle_amount > 0 then
						for particle_counter = 1, particle_amount do
							local random_timeout = random_generator:next(0, node_timer_interval)
							minetest.after(random_timeout, spawn_particle, pos, color_base_value, color_overlay_value)
						end
					end
					return true -- yes, run the timer again with the same interval
				end,
				on_destruct = function(pos)
					remove_ribbon(pos, color_overlay_name_lowercase)
					local node_timer = minetest.get_node_timer(pos)
					if node_timer ~= nil then
						if node_timer:is_started() then
							node_timer:stop()
						end
					end
				end
			})
			if has_mod_default and has_mod_dye then
				local output_name = mod_name..":"..color_base_name_lowercase.."_"..color_overlay_name_lowercase
				local dye_base = "dye:"..color_base_name_lowercase
				local dye_overlay = "dye:"..color_overlay_name_lowercase
				-- *sigh*
				if color_base_name_lowercase == "gray" then dye_base = "dye:grey" end
				if color_overlay_name_lowercase == "gray" then dye_overlay = "dye:grey" end
				-- *sigh* end
				if minetest.registered_craftitems[dye_base] ~= nil and minetest.registered_craftitems[dye_overlay] ~= nil and minetest.registered_craftitems[paper_item_string] ~= nil then
					local craft_input = {
						method = "normal",
						width = 3,
						items = { dye_base, dye_overlay, dye_base, dye_overlay, paper_item_string, dye_overlay, dye_base, dye_overlay, dye_base }
					}
					local craft_result, _ = minetest.get_craft_result(craft_input)
					if craft_result ~= nil and craft_result.item ~= nil and not craft_result.item:is_empty() then
						if has_unified_inventory then
							minetest.log("warning", "["..mod_name.."] There is already a crafting recipe registered with the same ingredients like '"..output_name.."' and the mod 'unified_inventory' is installed and active. '"..craft_result.item:get_name().."' is not craftable anymore!")
						end
					end
					minetest.register_craft({
						output = output_name,
						recipe = {
							{ dye_base, dye_overlay, dye_base },
							{ dye_overlay, paper_item_string, dye_overlay },
							{ dye_base, dye_overlay, dye_base }
						}
					})
					minetest.log("info", "["..mod_name.."] Registered crafting recipe for '"..mod_name..":"..color_base_name_lowercase.."_"..color_overlay_name_lowercase.."'.")
				else
					minetest.log("warning", "["..mod_name.."] Can't register crafting recipe for '"..output_name.."'. Missing ingredient(s).")
				end
			end
		end
	end
end

if minetest.get_modpath("default") ~= nil then has_mod_default = true end
if minetest.get_modpath("dye") ~= nil then has_mod_dye = true end
if minetest.get_modpath("unified_inventory") ~= nil then has_unified_inventory = true end

if not has_mod_default or not has_mod_dye then
	minetest.log("warning", "["..mod_name.."] Will not register crafting recipes. Missing mod(s) [has_mod_default="..tostring(has_mod_default)..",has_mod_dye="..tostring(has_mod_dye).."].")
end

for _, set in pairs(colors) do
	register_present(set[1], set[2])
end

--[[
	Wouldn't it be cool if Minetest would support different textures per nodebox section?
	That would make the ribbon-entities and its checks obsolete.
	https://github.com/minetest/minetest/issues/7889
]]--