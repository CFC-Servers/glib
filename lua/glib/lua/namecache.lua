local self = {}
GLib.Lua.NameCache = GLib.MakeConstructor (self)

function self:ctor ()
	local state = {}
	state.NameCache = GLib.WeakKeyTable ()
	state.QueuedTables = GLib.WeakKeyTable ()

	state.QueueTables = {}
	state.QueueTableNames = {}
	state.QueueSeparators = {}

	self.GetState = function (self)
		return state
	end

	self.Thread = nil

	self:GetState ().NameCache [_G] = "_G"
	self:GetState ().NameCache [debug.getregistry ()] = "_R"

	-- self:Index (GLib, "GLib")
	self:Index (_G, "")
	self:Index (debug.getregistry (), "_R")

	if CLIENT then
		local _, vguiControlTable = debug.getupvalue(vgui.Register, 1)
		self:Index (vguiControlTable, "[VGUI PanelFactory]")
	end

	hook.Add ("GLibSystemLoaded", "GLib.Lua.NameCache",
		function (systemName)
			self:Index (_G [systemName], systemName)
		end
	)
end

function self:GetFunctionName (func)
	return self:GetState ().NameCache [func]
end

function self:GetObjectName (object)
	return self:GetState ().NameCache [object]
end

function self:GetTableName (tbl)
	return self:GetState ().NameCache [tbl]
end

function self:IsIndexingThreadRunning ()
	if not self.Thread then return false end
	
	return not self.Thread:IsTerminated ()
end

function self:Index (tbl, tableName, dot)
	self:QueueIndex (tbl, tableName, dot)
	
	if not self:IsIndexingThreadRunning () then
		self:StartIndexingThread ()
	end
end

local tableNameBlacklist =
{
	-- Base GMod
	["stars"] = true,
	["_R._LOADED"] = true,
	["panelWidget"] = true,
	["motionsensor"] = true,
	["chathud.lines"] = true,
	["DComboBox.Derma"] = true,
	["chatsounds.List"] = true,
	["properties.List"] = true,
	["guiP_colourScheme"] = true,
	["chatsounds.ac.words"] = true,
	["chatsounds.SortedList"] = true,
	["chathud.markup.chunks"] = true,
	["chatsounds.SortedList2"] = true,
	["duplicator.EntityClasses"] = true,
	["duplicator.ConstraintType"] = true,
	["chatsounds.SortedListKeys"] = true,


	-- PAC
	["pac.OwnedParts"] = true,
	["pac.added_hooks"] = true,
	["pac.ActiveParts"] = true,
	["pac.particle_list"] = true,
	["pac.UniqueIDParts"] = true,
	["pac.PartTemplates"] = true,
	["pac.VariableOrder"] = true,
	["pac.webaudio.streams"] = true,
	["pace.example_outfits"] = true,
	["pac.registered_parts"] = true,
	["pac.EventArgumentCache"] = true,
	["pac.emut.active_mutators"] = true,
	["pac.BoneNameReplacements"] = true,
	["pac.animations.registered"] = true,
	["pac.emut.registered_mutators"] = true,
	["[VGUI PanelFactory].pace_luapad"] = true,

	-- GCompute and friends
	["VFS"] = true,
	["GLib"] = true,
	["GAuth"] = true,
	["Gooey"] = true,
	["GCompute"] = true,
	["Gooey.BasePanel"] = true, -- Indexed elsewhere I guess

	-- MNM
	["MNM.Decals.mapDecals"] = true,
	["MNM.Models.mapModelMeshes"] = true,
	["MNM.Materials.mapMaterials"] = true,
	["MNM.Queue.waitingForMaterial"] = true,
	["MNM.Models.staticPropsByModel"] = true,
	["MNM.Materials.mapMaterialData"] = true,
	["MNM.Entities.entityObjectIndices"] = true,
	["MNM.Materials.mapMaterialsLookup"] = true,

	-- NikNaks
	["NikNaks.CurrentMap._node"] = true,
	["NikNaks.CurrentMap._plane"] = true,
	["NikNaks.CurrentMap._faces"] = true,
	["NikNaks.CurrentMap._leafs"] = true,
	["NikNaks.CurrentMap._tinfo"] = true,
	["NikNaks.CurrentMap._tdata"] = true,
	["NikNaks.CurrentMap._bmodel"] = true,
	["NikNaks.CurrentMap._entities"] = true,
	["NikNaks.CurrentMap._gamelump"] = true,
	["NikNaks.CurrentMap._gamelumps"] = true,
	["NikNaks.CurrentMap._lumpheader"] = true,
	["NikNaks.CurrentMap._staticprops"] = true,
	["NikNaks.CurrentMap.staticPropsByModel"] = true,

	-- Stream Radio
	["StreamRadioLib.Settings"] = true,

	-- TFA
	["TFA.Attachments"] = true,
	["TFA.DataVersionMapping"] = true,

	-- Wire
	["EGP.Objects"] = true, -- Every single egp object, can expand indefinitely
	["GateActions"] = true, -- Static size, but includes all basic math operations that Wire Gates can perform
	["E2Lib.optable"] = true, -- 
	["WireGatesSorted"] = true,

	-- CW2
	["CustomizableWeaponry.sights"] = true, -- All registered signs and their info
	["CustomizableWeaponry.suppressors"] = true, -- All registered suppressors and their info
	["CustomizableWeaponry.shells.cache"] = true, -- Some shell cache? Gets pretty big
	["CustomizableWeaponry.registeredAttachments"] = true, -- Every single registered CW2 attachment
	["CustomizableWeaponry.registeredAttachmentsSKey"] = true, -- Some lookup table for the registeredAttachments

	-- Starfall
	["SF.Modules"] = true, -- Starfall Modules with all of their information, can get large
	["SF.Permissions"] = true, -- Static size but still a large table of starfall permissions

	-- CFC
	["CFCUlxCommands"] = true, -- All CFC commands and their metadata
	["SH_ANTICRASH.VARS"] = true,
	["SH_ANTICRASH.SETTINGS"] = true,
	["CustomPropInfo.Entries"] = true, -- All entities that have CustomPropInfo data received for them
	["gScoreboard.FancyGroups"] = true, -- The large group stylizing table in gScoreboard
	["cfcEntityStubber.oldWeaponStats"] = true, -- Contains multiple tables for every weapon we've ever stubbed or modified
	["CFCNotifications._settingsTemplate"] = true, -- Not too big, but still contains info that we don't need to index

	-- ACF
	["ACF.Tools"] = true,
	["ACF.Hitboxes"] = true, -- Long table containing all ACF hitbox data
	["ACF.MenuOptions"] = true, -- Tons of subtables and info about settings
	["ACF.DataCallbacks"] = true, -- All current data callbacks, scales up with ACF use

	-- ULX/ULib
	["ULib.ucl"] = true,
	["ULib.cmds"] = true, -- ULX Commands with all of their metadata
	["ULib.bans"] = true, -- Every single ban on the server
	["ulx.cvars"] = true, -- All cvars managed by ULX
	["urs.weapons"] = true, -- All weapons that have permission settings in URS
	["ULib.sayCmds"] = true, -- All sayable commands and their metadata
	["ULib.repcvars"] = true, -- All replicated cvars?
	["ulx.motdSettings"] = true, -- Long table of motd settings (that I don't think we even use?)
	["ulx.cmdsByCategory"] = true, -- Again, all commands and their metadata
	["ULib.translatedCmds"] = true, -- All commands again

	-- ULX's xgui
	["xgui.hook"] = true,
	["xgui.accesses"] = true,
	["xgui.dataTypes"] = true,
	["xgui.data.users"] = true,
	["xgui.data.teams"] = true,
	["xgui.data.accesses"] = true,
	["xgui.data.motdsettings"] = true,
	["xgui.data.URSRestrictions"] = true,

	-- Meta
	-- We use these locally for namecache timings
	["NameCacheTimings"] = true,
	["NameCacheCannotFindNames"] = true,

	-- Other
	["GPanel"] = true, -- Large Gooey element
	["MKeyboard"] = true, -- Musical Keyboard (contains lots of keys and sounds)
	["gb.Bitflags"] = true, -- Lots of enums
	["simfphys.LFS"] = true, -- Contains keybinds and other long tables
	["FPP.entOwners"] = true, -- All owner info for all entities on the map
	["MPRefreshButton"] = true,
	["HoverboardTypes"] = true, -- Lots of hoverboard types with metadata for each of them
	["webaudio.streams"] = true, -- All current webaudio streams, can expand indefinitely
	["prop2mesh.recycle"] = true,
	["Primitive.classes"] = true, -- All classes registered with Primitive Props
	["FPP.entTouchReasons"] = true, -- Touchability data for every entity on the map
	["matproxy.ActiveList"] = true, -- All active mat proxies, can expand indefinitely
	["Radial.radialToolPresets"] = true, -- All Radial preset settings
	["AdvDupe2.JobManager.Queue"] = true, -- Serverside, all Adv2s currently in progress
	["net.Stream.ReadStreamQueues"] = true, -- All existing Read Streams in NetStream
	["net.Stream.WriteStreamQueues"] = true, -- All existing Write Streams in NetStream
}

local numericTableNameBlacklist =
{
	["_R"] = true
}

local debug_getmetatable = debug.getmetatable

function self:ProcessTable (tbl, tableName, dot)
	if tableNameBlacklist [tableName] then return end
	local numericBlacklisted = numericTableNameBlacklist [tableName]

	local state = self:GetState ()
	local nameCache = state.NameCache
	local queuedTables = state.QueuedTables
	local Sleep = GLib.Sleep

	local CheckYield = GLib.CheckYield
	local ToCompactLuaString = GLib.Lua.ToCompactLuaString
	local IsValidVariableName = GLib.Lua.IsValidVariableName
	local IsStaticTable = GLib.IsStaticTable
	local GetMetaTable = GLib.GetMetaTable
	local QueueIndex = self.QueueIndex
	local type = type
	local tostring = tostring
	local SysTime = SysTime

	local loopCount = 0
	local totalTime = 0

	local sleepEvery = 100
	local sleepMs = 2

	for k, v in pairs (tbl) do
		CheckYield ()

		if loopCount > 0 and loopCount % sleepEvery == 0 then
			Sleep (sleepMs)
			CheckYield ()
		end

		local loopStart = SysTime ()
		local keyType = type (k)
		local valueType = type (v)

		if not numericBlacklisted or keyType ~= "number" then
			local memberName = nil

			if valueType == "function" or valueType == "table" then
				if keyType ~= "string" or not IsValidVariableName (k) then
					if keyType == "table" then
						-- ¯\_(ツ)_/¯
					end
					memberName = tableName .. " [" .. ToCompactLuaString (k) .. "]"
				else
					memberName = tableName ~= "" and (tableName .. dot .. tostring (k)) or tostring (k)
				end

				nameCache [v] = nameCache [v] or memberName
			end

			-- Recurse
			if valueType == "table" then
				if not queuedTables [v] then
					QueueIndex (self, v, memberName)

					-- Check if this is a GLib class
					if IsStaticTable (v) then
						local metatable = GetMetaTable (v)
						if type (metatable) == "table" then
							nameCache [metatable] = nameCache [metatable] or memberName
							QueueIndex (self, GetMetaTable (v), memberName, ":")
						end
					else
						-- Do the __index metatable if it exists
						local metatable = debug_getmetatable (v)
						local __index = metatable and metatable.__index or nil
						if __index and not queuedTables [__index] then
							QueueIndex (self, __index, memberName, ":")
						end
					end
				end
			end
		end

		totalTime = SysTime() - loopStart
		loopCount = loopCount + 1
	end

	return totalTime
end

do
	local type = type
	local table_insert = table.insert
	function self:QueueIndex (tbl, tableName, dot)
		if type (tbl) ~= "table" then
			return
		end

		dot = dot or "."

		local state = self:GetState ()

		if state.QueuedTables [tbl] then return end

		state.QueuedTables [tbl] = true
		table_insert (state.QueueTables, tbl)
		table_insert (state.QueueTableNames, tableName)
		table_insert (state.QueueSeparators, dot)
	end
end

function self:StartIndexingThread ()
	if self.Thread and not self.Thread:IsTerminated () then
		return
	end
	
	GLib.Debug ("GLib.Lua.NameCache : Indexing thread started.")

	local SysTime = SysTime
	local Sleep = GLib.Sleep
	local CheckYield = GLib.CheckYield
	local FormatDuration = GLib.FormatDuration
	local Debug = GLib.Debug

	local Thread = GLib.Threading.Thread ()
	self.Thread = Thread

	local totalCPUTime = 0
	local sleepMs = 5
	local sleepEvery = 100

	NameCacheTimings = {}
	NameCacheCannotFindNames = {}

	Thread:Start (
		function ()
			Sleep (1000)
			local state = self:GetState ()
			local QueueTables = state.QueueTables
			local QueueTableNames = state.QueueTableNames
			local QueueSeparators = state.QueueSeparators
			local table_insert = table.insert
			local ProcessTable = self.ProcessTable

			local i = 1
			local loopStart = SysTime()
			while i <= #QueueTables do
				CheckYield ()

				if i > 0 and i % sleepEvery == 0 then
					Sleep (sleepMs)
					CheckYield ()
				end

				local t = QueueTables[i]
				local tableName = QueueTableNames[i]
				local separator = QueueSeparators[i]

				-- Doesn't return a timing number if it was skipped (due to being blacklisted)
				local subtaskTime = ProcessTable (self, t, tableName, separator)
				if subtaskTime then
					if t == _G then tableName = "_G" end
					if tableName == "" or tableName == nil then
						NameCacheCannotFindNames[t] = true
					end

					totalCPUTime = totalCPUTime + subtaskTime

					table_insert (NameCacheTimings, { name = tableName, timing = subtaskTime })

					local timingStr = "Took: " .. GLib.FormatDuration (subtaskTime)

					Debug ("GLib.Lua.NameCache : Indexed: ", tableName, "", timingStr)
				end

				i = i + 1
			end

			local timeIndexing = SysTime () - loopStart
			local cpuTime = totalCPUTime

			Debug ("GLib.Lua.NameCache : Indexing took " .. FormatDuration (timeIndexing) .. ". ( CPU Time: " .. FormatDuration (cpuTime) .. ")")

			table.Empty (QueueTables)
			table.Empty (QueueTableNames)
			table.Empty (QueueSeparators)
			table.SortByMember (NameCacheTimings, "timing")
		end
	)
end

concommand.Add ("glib_namecache_timings", function (ply)
	if SERVER and ply:IsValid() then return end

	local header = Color( 15, 100, 200 )
	local label = Color( 200, 200, 200 )
	local name = Color( 25, 200, 25 )
	local value = Color( 200, 100, 25 )

	local MsgC = _G.MsgC
	MsgC (header, "[GLib] ")
	MsgC (label, "NameCache Timings:")
	MsgC ("\n")

	for i = 1, 20 do
		local item = NameCacheTimings[i]

		MsgC (label, " - [")
		MsgC (name, item.name)
		MsgC (label, "] = ")
		MsgC (value, GLib.FormatDuration (item.timing) )
		MsgC ("\n")
	end
end, nil, nil, FCVAR_UNREGISTERED )

GLib.Lua.NameCache = GLib.Lua.NameCache ()
