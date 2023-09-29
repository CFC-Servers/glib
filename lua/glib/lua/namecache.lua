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

function self:GetTableName (table)
	return self:GetState ().NameCache [table]
end

function self:IsIndexingThreadRunning ()
	if not self.Thread then return false end
	
	return not self.Thread:IsTerminated ()
end

function self:Index (table, tableName, dot)
	self:QueueIndex (table, tableName, dot)
	
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
	["_R.LOADED.derma"] = true,
	["derma"] = true,
	["_R.LOADED.matproxy.ActiveList"] = true,
	["matproxy.ActiveList"] = true,
	["motionsensor"] = true,
	["stars"] = true,

	["xgui.hook"] = true,
	["xgui.data.users"] = true,
	["xgui.data.teams"] = true,
	["xgui.data.accesses"] = true,
	["xgui.data.motdsettings"] = true,

	-- GLib
	["GLib.Loader.PackFileManager.MergedPackFileSystem.Root"] = true,
	["GLib.Lua.FunctionCache"] = true,

	-- GCompute
	["GCompute.GlobalNamespace"] = true,
	["GCompute.IDE.Instance.DocumentManager"] = true,
	["GCompute.IDE.Instance.ViewManager"] = true,
	["GCompute.LanguageDetector.Extensions"] = true,
	["GCompute.Languages.Languages.GLua.EditorHelper.RootNamespace"] = true,
	["GCompute.TypeSystem"] = true,
	["GCompute.Unicode:CategoryStage2"] = true,
	["GCompute.Loader:PackFileManager"] = true,
	["GCompute.Net:Layer2"] = true,
	["GCompute.Colors"] = true,
	["GCompute.AST.NumericLiteral"] = true,

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
	["pac.EventArgumentCache"] = true,
	["pac.animations.registered"] = true,
	["pac.BoneNameReplacements"] = true,

	-- VFS
	["VFS.RealRoot"] = true,
	["VFS.Root"] = true,

	-- GAuth
	["GAuth.Net"] = true,
	["GAuth.Groups"] = true,
	["GAuth.Loader"] = true,
	["GAuth.Colors"] = true,
	["GAuth.Protocol"] = true,
	["GAuth.Lua:Opcodes"] = true,

	-- MNM
	["MNM.Models.mapModelMeshes"] = true,
	["MNM.Queue.waitingForMaterial"] = true,
	["MNM.Materials.mapMaterialData"] = true,

	-- NikNaks
	["NikNaks.CurrentMap.staticPropsByModel"] = true,
	["NikNaks.CurrentMap._entities"] = true,
	["NikNaks.CurrentMap._plane"] = true,
	["NikNaks.CurrentMap._faces"] = true,
	["NikNaks.CurrentMap._leafs"] = true,
	["NikNaks.CurrentMap._node"] = true,
	["NikNaks.CurrentMap._tinfo"] = true,
	["NikNaks.CurrentMap._staticprops"] = true,
	["NikNaks.CurrentMap._lumpheader"] = true,

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

	-- CFC
	["cfcEntityStubber.oldWeaponStats"] = true,
	["gScoreboard.FancyGroups"] = true,
	["SH_ANTICRASH.VARS"] = true,
	["SH_ANTICRASH.SETTINGS"] = true,
	["CustomPropInfo.Entries"] = true,

	-- Other
	["gb.Bitflags"] = true,
	["HoverboardTypes"] = true,
	["MKeyboard"] = true,
	["ACF.DataCallbacks"] = true,
	["ACF.Hitboxes"] = true,
	["ACF.Tools"] = true,
	["ACF.MenuOptions"] = true,
	["ULib.translatedCmds"] = true,
	["ULib.cmds.translatedCmds"] = true,
	["ULib.ucl.authed"] = true,
	["ulx.cmdsByCategory"] = true,
	["Primitive.classes"] = true,
	["webaudio.streams"] = true,
	["urs.weapons"] = true,
	["prop2mesh.recycle"] = true,
	["simfphys.LFS"] = true,
	["Radial.radialToolPresets"] = true,
	["net.Stream.ReadStreamQueues"] = true,
	["NameCacheTimings"] = true,

}

local numericTableNameBlacklist =
{
	["_R"] = true
}

local debug_getmetatable = debug.getmetatable

function self:ProcessTable (table, tableName, dot)
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

	for k, v in pairs (table) do
		CheckYield ()
		
		local keyType = type (k)
		local valueType = type (v)
		
		if not numericBlacklisted or
		   keyType ~= "number" then
			local memberName = nil
			
			if valueType == "function" or
			   valueType == "table" then
				if keyType ~= "string" or
				   not IsValidVariableName (k) then
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
						if __index and
						   not queuedTables [__index] then
							QueueIndex (self, __index, memberName, ":")
						end
					end
				end
			end
		end
	end
end

function self:QueueIndex (table, tableName, dot)
	if type (table) ~= "table" then
		return
	end
	
	dot = dot or "."
	
	local state = self:GetState ()
	
	if state.QueuedTables [table] then return end
	
	state.QueuedTables [table] = true
	state.QueueTables [#state.QueueTables + 1] = table
	state.QueueTableNames [#state.QueueTableNames + 1] = tableName
	state.QueueSeparators [#state.QueueSeparators + 1] = dot
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
			local ProcessTable = self.ProcessTable

			while #QueueTables > 0 do
				CheckYield ()

				local t = table_remove (QueueTables)
				local tableName = table_remove (QueueTableNames)
				local separator = table_remove (QueueSeparators)

				local startTime = SysTime()
				ProcessTable (self, t, tableName, separator)
				table.insert (NameCacheTimings, { name = tableName, timing = SysTime() - startTime })
				Debug ("GLib.Lua.NameCache : Indexed: ", tableName)
			end

			table.SortByMember (NameCacheTimings, "timing")
			Debug ("GLib.Lua.NameCache : Indexing took " .. FormatDuration (SysTime () - GetStartTime (Thread)) .. ".")
		end
	)
end

GLib.Lua.NameCache = GLib.Lua.NameCache ()
