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
	
	self:Index (GLib, "GLib")
	self:Index (_G, "")
	self:Index (debug.getregistry (), "_R")
	
	if CLIENT then
		local _, vguiControlTable = debug.getupvalue(vgui.Register, 1)
		self:Index (vguiControlTable, "")
	end
	
	hook.Add ("GLibSystemLoaded", "GLib.Lua.NameCache",
		function (systemName)
			self:Index (_G [systemName], systemName)
			
			if CLIENT then
				local _, vguiControlTable = debug.getupvalue(vgui.Register, 1)
				self:GetState ().QueuedTables [vguiControlTable] = nil
				self:Index (vguiControlTable, "")
			end
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
	["chathud.lines"] = true,
	["chathud.markup.chunks"] = true,
	["chatsounds.ac.words"] = true,
	["chatsounds.List"] = true,
	["chatsounds.SortedList"] = true,
	["chatsounds.SortedList2"] = true,
	["chatsounds.SortedListKeys"] = true,
	["panelWidget"] = true,
	["guiP_colourScheme"] = true,
	["_R._LOADED"] = true,
	["motionsensor"] = true,
	["stars"] = true,
	["DComboBox.Derma"] = true,
	["duplicator.EntityClasses"] = true,

	["xgui.hook"] = true,
	["xgui.accesses"] = true,
	["xgui.dataTypes"] = true,
	["xgui.data.users"] = true,
	["xgui.data.teams"] = true,
	["xgui.data.accesses"] = true,
	["xgui.data.motdsettings"] = true,

	-- GLib
	["GLib"] = true,
	["GLib.Lua"] = true,
	["GLib.Colors"] = true,
	["GLib.GlobalNamespace"] = true,
	["GLib.Lua.FunctionCache"] = true,
	["GLib.CodeExporter"] = true,
	["GLib.Rendering"] = true,
	["GLib.Threading"] = true,
	["GLib.Networking"] = true,
	["GLib.Loader"] = true,
	["GLib.Containers"] = true,
	["GLib.PlayerMonitor"] = true,
	["GLib.Net"] = true,
	["GLib.Loader.PackFileManager.MergedPackFileSystem.Root"] = true,

	-- GCompute
	["GCompute"] = true,
	["GCompute.AST"] = true,
	["GCompute.Lua"] = true,
	["GCompute.Net"] = true,
	["GCompute.GLua"] = true,
	["GCompute.Text"] = true,
	["GCompute.Colors"] = true,
	["GCompute.System"] = true,
	["GCompute.Lexing"] = true,
	["GCompute.Unicode"] = true,
	["GCompute.Services"] = true,
	["GCompute.Namespace"] = true,
	["GCompute.Execution"] = true,
	["GCompute.Languages"] = true,
	["GCompute.Net:Layer2"] = true,
	["GCompute.TypeSystem"] = true,
	["GCompute.CodeExporter"] = true,
	["GCompute.SyntaxColoring"] = true,
	["GCompute.GlobalNamespace"] = true,
	["GCompute.MirrorNamespace"] = true,
	["GCompute.ClassDefinition"] = true,
	["GCompute.MethodDefinition"] = true,
	["GCompute.LanguageDetector"] = true,
	["GCompute.AST.NumericLiteral"] = true,
	["GCompute.NamespaceDefinition"] = true,
	["GCompute.AST.AnonymousFunction"] = true,
	["GCompute.Unicode:CategoryStage1"] = true,
	["GCompute.Unicode:CategoryStage2"] = true,
	["GCompute.Loader:PackFileManager"] = true,
	["GComputeFileChangeNotificationBar"] = true,
	["GCompute.IDE.Instance.ViewManager"] = true,
	["GCompute.LanguageDetector.Extensions"] = true,
	["GCompute.IDE.Instance.DocumentManager"] = true,
	["GCompute.Services.RemoteServiceManagerManager"] = true,
	["GCompute.Languages.Languages.GLua.EditorHelper.RootNamespace"] = true,

	-- PAC
	["pac.ActiveParts"] = true,
	["pac.OwnedParts"] = true,
	["pac.UniqueIDParts"] = true,
	["pac.webaudio.streams"] = true,
	["pace.example_outfits"] = true,
	["pac.PartTemplates"] = true,
	["pac.VariableOrder"] = true,
	["pac.added_hooks"] = true,
	["pac.registered_parts"] = true,
	["pac.emut.registered_mutators"] = true,
	["pac.emut.active_mutators"] = true,
	["pac.EventArgumentCache"] = true,
	["pac.animations.registered"] = true,
	["pac.BoneNameReplacements"] = true,

	-- VFS
	["VFS"] = true,

	-- GAuth
	["GAuth"] = true,

	-- Gooey
	["Gooey"] = true,

	-- MNM
	["MNM.Models.mapModelMeshes"] = true,
	["MNM.Queue.waitingForMaterial"] = true,
	["MNM.Materials.mapMaterialData"] = true,

	-- NikNaks
	["NikNaks.CurrentMap.staticPropsByModel"] = true,
	["NikNaks.CurrentMap._node"] = true,
	["NikNaks.CurrentMap._plane"] = true,
	["NikNaks.CurrentMap._faces"] = true,
	["NikNaks.CurrentMap._leafs"] = true,
	["NikNaks.CurrentMap._tinfo"] = true,
	["NikNaks.CurrentMap._gamelump"] = true,
	["NikNaks.CurrentMap._entities"] = true,
	["NikNaks.CurrentMap._gamelumps"] = true,
	["NikNaks.CurrentMap._lumpheader"] = true,
	["NikNaks.CurrentMap._staticprops"] = true,

	-- Stream Radio
	["StreamRadioLib.Settings"] = true,

	-- TFA
	["TFA.DataVersionMapping"] = true,
	["TFA.Attachments"] = true,

	-- Wire
	["WireGatesSorted"] = true,
	["E2Lib.optable"] = true,
	["EGP.Objects"] = true,
	["GateActions"] = true,

	-- CW2
	["CustomizableWeaponry.sights"] = true,
	["CustomizableWeaponry.suppressors"] = true,
	["CustomizableWeaponry.shells.cache"] = true,
	["CustomizableWeaponry.registeredAttachments"] = true,
	["CustomizableWeaponry.registeredAttachmentsSKey"] = true,

	-- Starfall
	["SF.Permissions"] = true,
	["SF.Modules"] = true,

	-- CFC
	["cfcEntityStubber.oldWeaponStats"] = true,
	["gScoreboard.FancyGroups"] = true,
	["SH_ANTICRASH.VARS"] = true,
	["SH_ANTICRASH.SETTINGS"] = true,
	["CustomPropInfo.Entries"] = true,
	["CFCUlxCommands"] = true,

	-- ACF
	["ACF.DataCallbacks"] = true,
	["ACF.Hitboxes"] = true,
	["ACF.Tools"] = true,
	["ACF.MenuOptions"] = true,

	-- ULX/ULib
	["ULib.cmds"] = true,
	["urs.weapons"] = true,
	["ULib.sayCmds"] = true,
	["ULib.repcvars"] = true,
	["ULib.ucl.users"] = true,
	["ULib.ucl.authed"] = true,
	["ulx.cmdsByCategory"] = true,
	["ulx.motdSettings"] = true,
	["ulx.cvars"] = true,
	["ULib.translatedCmds"] = true,

	-- Other
	["gb.Bitflags"] = true,
	["HoverboardTypes"] = true,
	["MKeyboard"] = true,
	["Primitive.classes"] = true,
	["webaudio.streams"] = true,
	["prop2mesh.recycle"] = true,
	["simfphys.LFS"] = true,
	["Radial.radialToolPresets"] = true,
	["net.Stream.ReadStreamQueues"] = true,
	["NameCacheTimings"] = true,
	["GPanel"] = true,
	["MPRefreshButton"] = true,
	["FPP.entTouchReasons"] = true,
	["matproxy.ActiveList"] = true,
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

	local CheckYield = GLib.CheckYield
	local ToCompactLuaString = GLib.Lua.ToCompactLuaString
	local IsValidVariableName = GLib.Lua.IsValidVariableName
	local IsStaticTable = GLib.IsStaticTable
	local GetMetaTable = GLib.GetMetaTable
	local QueueIndex = self.QueueIndex
	local type = type
	local tostring = tostring
	local SysTime = SysTime

	local loopStart
	local totalTime = 0

	for k, v in pairs (tbl) do
		if loopStart then
			totalTime = totalTime + ( SysTime() - loopStart )
		end

		CheckYield ()

		loopStart = SysTime()
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
	end

	if loopStart then
		totalTime = totalTime + ( SysTime() - loopStart )
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
	local GetStartTime = Thread.GetStartTime

	NameCacheTimings = {}

	Thread:Start (
		function ()
			Sleep (1000)

			local state = self:GetState ()
			local QueueTables = state.QueueTables
			local QueueTableNames = state.QueueTableNames
			local QueueSeparators = state.QueueSeparators
			local table_remove = table.remove
			local table_insert = table.insert
			local ProcessTable = self.ProcessTable

			while #QueueTables > 0 do
				CheckYield ()

				local t = table_remove (QueueTables)
				local tableName = table_remove (QueueTableNames)
				local separator = table_remove (QueueSeparators)

				-- Doesn't return a timing number if it was skipped (due to being blacklisted)
				local totalTime = ProcessTable (self, t, tableName, separator)
				if totalTime then
					table_insert (NameCacheTimings, { name = tableName, timing = totalTime })
					Debug ("GLib.Lua.NameCache : Indexed: ", tableName)
				end
			end

			table.SortByMember (NameCacheTimings, "timing")
			Debug ("GLib.Lua.NameCache : Indexing took " .. FormatDuration (SysTime () - GetStartTime (Thread)) .. ".")
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
		MsgC (value, item.timing .. "")
		MsgC ("\n")
	end
end, nil, nil, FCVAR_UNREGISTERED )

GLib.Lua.NameCache = GLib.Lua.NameCache ()
