GLib.Loader = {}
GLib.Loader.File = {}


for k, v in pairs (file) do
	GLib.Loader.File [k] = v
end

CreateConVar ("glib_debug_prints", 0, FCVAR_ARCHIVE, "GLib Debug Prints", 0, 1)
if CLIENT then
	CreateClientConVar ("glib_use_local_files", 0, true, false)
	CreateClientConVar ("glib_autoload_enabled", 0, true, false)
end

function GLib.Loader.CompileFile (path)
	local _, compiled = GLib.Loader.File.Read (path, "LUA")
	if compiled then return compiled end

	return CompileFile (path)
end

do
	local string_find = string.find
	local string_sub = string.sub
	local isfunction = isfunction
	local CompileString = CompileString
	function GLib.Loader.CompileString (code, path, errorMode)
		if string_find (code, "^\xef\xbb\xbf") then
			code = string_sub (code, 4)
		end

		local compiled = CompileString (code, path, errorMode)
		if isfunction (compiled) then
			setfenv (compiled, GLib.Loader.Environment)
		end
		return compiled
	end
end

local localLuaPathId = CLIENT and "LCL" or "LSV"
function GLib.Loader.File.Exists (path, pathId)
	if pathId ~= "LUA" and pathId ~= localLuaPathId then return file.Exists (path, pathId) end

	if file.Exists (path, pathId) then return true end
	if GLib.Loader.PackFileManager:GetMergedPackFileSystem ():Exists (path) then return true end
	return false
end

function GLib.Loader.File.Find (path, pathId)
	if pathId ~= "LUA" and pathId ~= localLuaPathId then return file.Find (path, pathId) end

	local files, folders = file.Find (path, pathId)
	local fileSet = {}
	local folderSet = {}

	for _, v in ipairs (files  ) do fileSet   [v:lower ()] = true end
	for _, v in ipairs (folders) do folderSet [v:lower ()] = true end

	local files2, folders2 = GLib.Loader.PackFileManager:GetMergedPackFileSystem ():Find (path)
	for _, v in ipairs (files2) do
		if not fileSet [v:lower ()] then files [#files + 1] = v end
	end
	for _, v in ipairs (folders2) do
		if not folderSet [v:lower ()] then folders [#folders + 1] = v end
	end
	return files, folders
end

function GLib.Loader.File.Read (path, pathId)
	if pathId ~= "LUA" and pathId ~= localLuaPathId then return file.Read (path, pathId) end
	local otherPathId = pathId == "LUA" and localLuaPathId or "LUA"
	local canRunLocal = pathId == localLuaPathId or GetConVar ("sv_allowcslua"):GetBool ()

	-- pathId is LUA or LCL, assume that we're trying to include () the file.

	local contents = nil
	local compiled = nil
	if GLib.Loader.ShouldPackOverrideLocalFiles () then
		-- Check pack file
		contents, compiled = GLib.Loader.PackFileManager:GetMergedPackFileSystem ():Read (path)

		-- Check given path
		if not contents and not compiled and
			file.Exists (path, pathId) then
			contents = file.Read (path, pathId)
			compiled = function ()
				include (path)
			end
		end

		-- Check other path
		local canRunOtherPath = otherPathId == "LUA" or canRunLocal
		if not contents and not compiled and canRunOtherPath and file.Exists (path, otherPathId) then
			contents = file.Read (path, otherPathId)
			compiled = function ()
				include (path)
			end
		end
	else
		-- Check LCL path
		if canRunLocal and file.Exists (path, localLuaPathId) then
			contents = file.Read (path, localLuaPathId)
			compiled = function ()
				include (path)
			end
		end

		-- Check pack file
		if not contents and not compiled then
			contents, compiled = GLib.Loader.PackFileManager:GetMergedPackFileSystem ():Read (path)
		end

		-- Check LUA path
		if not contents and not compiled and file.Exists (path, "LUA") then
			contents = file.Read (path, "LUA")
			compiled = function ()
				include (path)
			end
		end
	end
	return contents, compiled
end

GLib.Loader.Exists = GLib.Loader.File.Exists
GLib.Loader.Find   = GLib.Loader.File.Find
GLib.Loader.Read   = GLib.Loader.File.Read

local pathStack = { "" }
do
	local debug_getinfo = debug.getinfo
	local string_sub = string.sub
	local string_match = string.match
	local string_find = string.find
	local isfunction = isfunction
	local xpcall = xpcall
	local tostring = tostring

	local Read = GLib.Loader.File.Read
	local GLibError = GLib.Error

	function GLib.Loader.Include (path)
		local callerPath = debug_getinfo (2).short_src
		if string_sub (callerPath, 1, 1) == "@" then callerPath = string_sub (callerPath, 2) end

		callerPath = string_match (callerPath, "lua/(.*)") or callerPath

		local callerDirectory = ""
		if string_find (callerPath, "/") then
			callerDirectory = string_sub (callerPath, 1, string_find (callerPath, "/[^/]*$"))
		else
			callerDirectory = ""
		end

		local fullPath = pathStack [#pathStack] .. path
		local code, compiled = Read (pathStack [#pathStack] .. path, "LUA")
		if not code and not compiled then
			fullPath = callerDirectory .. path
			code, compiled = Read (callerDirectory .. path, "LUA")
		end

		if not code and not compiled then
			fullPath = path
			code, compiled = Read (path, "LUA")
		end

		if not code and not compiled then
			GLib.Error ("GLib.Loader.Include : " .. path .. ": File not found (Path was " .. pathStack [#pathStack] .. ", caller path was " .. callerDirectory .. ").\n")
		else
			compiled = compiled or GLib.Loader.CompileString (code, "lua/" .. fullPath, false)

			if isfunction (compiled) then
				pathStack [#pathStack + 1] = string_sub (fullPath, 1, string_find (fullPath, "/[^/]*$"))
				return (
					function (success, ...)
						pathStack [#pathStack] = nil
						if not success then return end
						return ...
					end
				) (xpcall (compiled, GLibError))
			else
				ErrorNoHalt ("GLib.Loader.Include : " .. fullPath .. ": File failed to compile:\n\t" .. tostring (compiled) .. "\n")
			end
		end
	end
end

GLib.Loader.Environment = setmetatable (
	{
		AddCSLuaFile = function () end,
		file         = GLib.Loader.File,
		include      = GLib.Loader.Include,
		CompileFile  = GLib.Loader.CompileFile,
		gfile        = _G.file,
	},
	{
		__index = getfenv (),
		__newindex = function (_, k, v)
			getfenv () [k] = v
		end
	}
)

function GLib.Loader.RunPackFile (executionTarget, packFileSystem, callback)
	callback = callback or GLib.NullCallback

	local shouldRun = executionTarget == "sh"
	shouldRun = shouldRun or executionTarget == "m"
	if SERVER and executionTarget == "sv" then shouldRun = true end
	if CLIENT and executionTarget == "cl" then shouldRun = true end

	if shouldRun then
		do
			for i = 1, packFileSystem:GetSystemTableCount () do
				GLib.Loader.PackFileManager:GetMergedPackFileSystem ():AddSystemTable (packFileSystem:GetSystemTableName (i))
			end

			if GLib.Loader.ShouldPackOverrideLocalFiles () then
				-- Unload systems in reverse load order
				for i = packFileSystem:GetSystemTableCount (), 1, -1 do
					local systemTableName = packFileSystem:GetSystemTableName (i)
					if systemTableName == "GLib" then
						_G [systemTableName].Stage2 = nil
					elseif _G [systemTableName] then
						print ("GLib.Loader : Unloading " .. systemTableName .. " to prepare for replacement...")
						GLib.UnloadSystem (systemTableName)
					end
				end
			end

		end

		packFileSystem:MergeInto (GLib.Loader.PackFileManager:GetMergedPackFileSystem ())
		local Include = GLib.Loader.Include

		do
			-- Shared autoruns
			local files, _ = packFileSystem:Find ("autorun/*.lua")
			for _, fileName in ipairs (files) do
				Include ("autorun/" .. fileName)
			end
		end

		do
			-- Local autoruns
			local files, _ = packFileSystem:Find ("autorun/" .. (SERVER and "server" or "client") .. "/*.lua")
			for _, fileName in ipairs (files) do
				Include ("autorun/" .. (SERVER and "server" or "client") .. "/" .. fileName)
			end
		end

		-- Events
		for i = 1, packFileSystem:GetSystemTableCount () do
			local systemTableName = packFileSystem:GetSystemTableName (i)
			GLib:DispatchEvent ("PackFileLoaded", systemTableName)
		end

		GLib.CallDelayed( function() callback (true) end )
	else
		GLib.CallDelayed( function() callback (false) end )
	end
end

function GLib.Loader.RunSerializedPackFile (executionTarget, serializedPackFile, compressed, packFileName, callback)
	callback = callback or GLib.NullCallback

	local shouldRun = executionTarget == "sh"
	shouldRun = shouldRun or executionTarget == "m"
	if SERVER and executionTarget == "sv" then shouldRun = true end
	if CLIENT and executionTarget == "cl" then shouldRun = true end

	if shouldRun then
		local packFileSystem = GLib.Loader.PackFileSystem ()
		packFileSystem:SetName (packFileName)
		local startTime = SysTime ()
		packFileSystem:Deserialize (serializedPackFile, compressed,
			function (decompressedSize)
				local fileSize = GLib.FormatFileSize (#serializedPackFile)
				if compressed then
					fileSize = fileSize .. " decompressed to " .. GLib.FormatFileSize (decompressedSize)
				end

				Msg ("GLib.Loader : Running pack file \"" .. packFileSystem:GetName () .. "\", deserialization took " .. GLib.FormatDuration (SysTime () - startTime) .. " (" .. packFileSystem:GetFileCount () .. " total files, " .. fileSize .. ")...")
				startTime = SysTime ()
				GLib.Loader.RunPackFile (executionTarget, packFileSystem, callback)
				MsgN (" took " .. GLib.FormatDuration (SysTime () - startTime) .. ".")
			end
		)
	else
		callback (false)
	end
end

function GLib.Loader.ShouldPackOverrideLocalFiles ()
	if SERVER then return true end
	if not GetConVar ("sv_allowcslua"):GetBool () then return true end
	return not GetConVar ("glib_use_local_files"):GetBool ()
end

function GLib.Loader.StreamPack (destinationId, executionTarget, compressedSerializedPackFile, displayName)
	local outBuffer = GLib.StringOutBuffer ()
	outBuffer:String (executionTarget)
	outBuffer:String (displayName or "<unnamed>")
	outBuffer:LongString (compressedSerializedPackFile)

	GLib.Transfers.Send (destinationId, "GLib.LuaPack", outBuffer:GetString ())
end

local function IsUserIdSuperAdmin (userId)
	if userId == "Server" then return true end

	for _, v in ipairs (player.GetAll ()) do
		if GLib.GetPlayerId (v) == userId then
			return v:IsSuperAdmin ()
		end
	end

	return false
end

GLib.Transfers.RegisterHandler ("GLib.LuaPack",
	function (userId, data)
		if SERVER and not IsUserIdSuperAdmin (userId) then return end

		local inBuffer = GLib.StringInBuffer (data)
		local executionTarget = inBuffer:String ()
		local displayName = inBuffer:String ()
		local compressedSerializedPackFile = inBuffer:LongString ()

		GLib.Loader.RunSerializedPackFile (executionTarget, compressedSerializedPackFile, true, displayName)
	end
)

GLib.Transfers.RegisterInitialPacketHandler ("GLib.LuaPack",
	function (userId, data)
		if SERVER and not IsUserIdSuperAdmin (userId) then
			local inBuffer = GLib.StringInBuffer (data)
			local executionTarget = inBuffer:String ()
			local displayName = inBuffer:String ()

			print ("GLib.Loader : Rejecting lua pack " .. displayName .. " from " .. userId .. ".")
			ErrorNoHaltWithStack ("GLib.Loader : Rejecting lua pack " .. displayName .. " from " .. userId .. ".")
			return false
		end
	end
)

if SERVER then
	concommand.Add ("glib_request_pack",
		function (ply)
			if not ply or not ply:IsValid () then return end

			GLib.Loader.PackFileManager:GenerateResources ()

			local outBuffer = GLib.StringOutBuffer ()
			GLib.Loader.PackFileManager:SerializeManifest (outBuffer)
			GLib.Transfers.Send (GLib.GetPlayerId (ply), "GLib.Loader.Manifest", outBuffer:GetString ())
		end
	)
elseif CLIENT then
	GLib.Transfers.RegisterHandler ("GLib.Loader.Manifest",
		function (userId, data)
			local inBuffer = GLib.StringInBuffer (data)
			local packFileEntries = {}

			local resourceId = inBuffer:String ()
			while resourceId ~= "" do
				local versionHash = inBuffer:String ()
				packFileEntries [#packFileEntries + 1] =
				{
					ResourceId     = resourceId,
					VersionHash    = versionHash,
					Data           = nil,
					PackFileSystem = GLib.Loader.PackFileSystem ()
				}
				packFileEntries [#packFileEntries].PackFileSystem:SetName (resourceId)

				resourceId = inBuffer:String ()
			end

			print ("GLib.Loader : Received manifest (" .. #packFileEntries .. " pack file" .. (#packFileEntries == 1 and "" or "s") .. ").")

			local i = 1
			local requestNextResource
			local deserializeNextPackFile
			local runNextPackFile

			function requestNextResource ()
				if i > #packFileEntries then
					-- Finished requesting pack files, run them all.
					i = 1
					deserializeNextPackFile ()
					return
				end

				GLib.Resources.Get ("LuaPack", packFileEntries [i].ResourceId, packFileEntries [i].VersionHash,
					function (success, data)
						if not success then
							GLib.Error ("GLib.Loader : Failed to get resource " .. packFileEntries [i].ResourceId .. " (" .. packFileEntries [i].VersionHash .. ").")
						end

						packFileEntries [i].Data = data

						i = i + 1
						requestNextResource ()
					end
				)
			end

			function deserializeNextPackFile ()
				if i > #packFileEntries then
					-- Finished deserializing pack files, run them all.
					i = 1
					runNextPackFile ()
					return
				end

				local startTime = SysTime ()
				local packFileEntry = packFileEntries [i]
				local packFileSystem = packFileEntries [i].PackFileSystem

				if packFileEntries [i].Data then
					packFileSystem:Deserialize (packFileEntries [i].Data, false,
						function ()
							packFileEntry.DeserializationDuration = SysTime () - startTime

							i = i + 1
							deserializeNextPackFile ()
						end
					)
				else
					i = i + 1
					deserializeNextPackFile ()
				end
			end

			function runNextPackFile ()
				if i > #packFileEntries then
					-- Finished running pack files.
					MsgN ("GLib.Loader : Ran all pack files!")
					GLib.Loader.AllPacksLoaded = true
					return
				end

				local startTime = SysTime ()
				local packFileEntry = packFileEntries [i]
				local packFileSystem = packFileEntries [i].PackFileSystem
				local fileSize = GLib.FormatFileSize (#packFileEntries [i].Data)
				MsgN ("GLib.Loader : Running pack file \"" .. packFileSystem:GetName () .. "\", deserialization took " .. GLib.FormatDuration (packFileEntry.DeserializationDuration) .. " (" .. packFileSystem:GetFileCount () .. " total files, " .. fileSize .. ").")
				GLib.Loader.RunPackFile ("m", packFileSystem,
					function ()
						MsgN ("GLib.Loader : Ran pack file " .. packFileSystem:GetName () .. " in " .. GLib.FormatDuration (SysTime () - startTime) .. ".")
						i = i + 1
						GLib.CallDelayed (runNextPackFile)
					end
				)
			end

			requestNextResource ()
		end
	)

	GLib.WaitForLocalPlayer (
		function ()
			timer.Simple (5,
				function ()
					if not GetConVar( "glib_autoload_enabled" ):GetBool() then return end
					RunConsoleCommand ("glib_request_pack")
				end
			)
		end
	)
end
