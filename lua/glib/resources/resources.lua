GLib.Resources = {}
GLib.Resources.Resources = {}

function GLib.Resources.Get (namespace, id, callback)
	namespace = namespace or ""
	callback = callback or GLib.NullCallback
	
	local resource = GLib.Resources.Resources [namespace .. "/" .. id]
	if resource then
		-- Resource has already been requested.
		-- Resource may or may not be fully received.
		
		if resource:IsAvailable () then
			callback (true, resource:GetData ())
			return
		elseif resource:GetState () == GLib.Resources.ResourceState.Unavailable then
			callback (false)
			return
		end
		
		-- Otherwise we're waiting for a response from the server or
		-- in the process of receiving the resource
	else
		-- Server has nowhere to request resources from.
		if SERVER then callback (false) return end
		
		-- Clients should request the resource from the server.
		resource = GLib.Resources.Resource (namespace, id)
		GLib.Resources.Resources [namespace .. "/" .. id] = resource
		
		-- Prepare transfer request arguments
		local outBuffer = GLib.StringOutBuffer ()
		outBuffer:String (namespace)
		outBuffer:String (id)
		
		-- Send transfer request
		print ("GLib.Resources : Requesting resource " .. namespace .. "/" .. id .. "...")
		local transfer = GLib.Transfers.Request ("Server", "GLib.Resources", outBuffer:GetString ())
		transfer:AddEventListener ("Finished",
			function (_)
				local inBuffer = GLib.StringInBuffer (transfer:GetData ())
				local namespace = inBuffer:String ()
				local id = inBuffer:String ()
				local versionHash = inBuffer:String ()
				
				local startTime = SysTime ()
				local compressed = inBuffer:LongString ()
				local data = util.Decompress (compressed)
				
				print ("GLib.Resources : Received resource " .. namespace .. "/" ..id .. " (" .. GLib.FormatFileSize (#compressed) .. " decompressed to " .. GLib.FormatFileSize (#data) .. " in " .. GLib.FormatDuration (SysTime () - startTime) .. ").")
				
				if resource:IsCacheable () then
					GLib.Resources.ResourceCache:CacheResource (resource:GetNamespace (), resource:GetId (), resource:GetVersionHash (), data)
					resource:SetLocalPath ("data/" .. GLib.Resources.ResourceCache:GetCachePath (resource:GetNamespace (), resource:GetId (), resource:GetVersionHash ()))
				end
				
				resource:SetData (data)
				resource:SetState (GLib.Resources.ResourceState.Available)
			end
		)
		transfer:AddEventListener ("RequestRejected",
			function (_, rejectionData)
				print ("GLib.Resources : Request for resource " .. namespace .. "/" .. id .. " has been rejected.")
				resource:SetState (GLib.Resources.ResourceState.Unavailable)
			end
		)
	end
	
	resource:AddEventListener ("StateChanged",
		function (resource, state)
			if state == GLib.Resources.ResourceState.Unavailable then
				callback (false)
			elseif state == GLib.Resources.ResourceState.Available then
				callback (true, resource:GetData ())
			end
		end
	)
end

function GLib.Resources.RegisterData (namespace, id, data)
	local resource = GLib.Resources.Resource (namespace, id)
	resource:SetData (data)
	resource:SetState (GLib.Resources.ResourceState.Available)
	
	GLib.Resources.Resources [namespace .. "/" .. id] = resource
	
	print ("GLib.Resources : Resource " .. namespace .. "/" .. id .. " registered (" .. GLib.FormatFileSize (#data) .. ").")
	
	return resource
end

function GLib.Resources.RegisterFile (namespace, id, localPath)
	if not file.Exists (localPath, "GAME") then return nil end
	
	local resource = GLib.Resources.Resource (namespace, id)
	resource:SetLocalPath (localPath)
	resource:SetState (GLib.Resources.ResourceState.Available)
	
	GLib.Resources.Resources [namespace .. "/" .. id] = resource
	
	print ("GLib.Resources : Resource " .. namespace .. "/" .. id .. " registered (" .. localPath .. ").")
	
	return resource
end

GLib.Transfers.RegisterHandler ("GLib.Resources", GLib.NullCallback)

GLib.Transfers.RegisterRequestHandler ("GLib.Resources",
	function (userId, data)
		local inBuffer = GLib.StringInBuffer (data)
		local namespace = inBuffer:String ()
		local id = inBuffer:String ()
		
		local resource = GLib.Resources.Resources [namespace .. "/" .. id]
		if not resource then
			-- Resource not found.
			-- I'm sorry, Dave. I'm afraid I can't do that.
			print ("GLib.Resources : Rejecting resource request for " .. namespace .. "/" .. id .. " from " .. userId .. ".")
			return false
		end
		
		print ("GLib.Resources : Sending resource " .. namespace .. "/" .. id .. " to " .. userId .. ".")
		local outBuffer = GLib.StringOutBuffer (data)
		outBuffer:String (namespace)
		outBuffer:String (id)
		outBuffer:String (resource:GetVersionHash ())
		outBuffer:LongString (resource:GetCompressedData ())
		return true, outBuffer:GetString ()
	end
)

GLib.Transfers.RegisterInitialPacketHandler ("GLib.Resources",
	function (userId, data)
		local inBuffer = GLib.StringInBuffer (data)
		local namespace = inBuffer:String ()
		local id = inBuffer:String ()
		local versionHash = inBuffer:String ()
		
		local resource = GLib.Resources.Resources [namespace .. "/" .. id]
		if not resource then
			-- We never asked for this.
			-- Cancel the transfer.
			return false
		end
		
		resource:SetVersionHash (versionHash)
		resource:SetState (GLib.Resources.ResourceState.Receiving)
		
		if GLib.Resources.ResourceCache:IsResourceCached (namespace, id, versionHash) then
			resource:SetLocalPath ("data/" .. GLib.Resources.ResourceCache:GetCachePath (namespace, id, versionHash))
			resource:SetState (GLib.Resources.ResourceState.Available)
			
			GLib.Resources.ResourceCache:UpdateLastAccessTime (namespace, id, versionHash)
			
			-- We've got the resource cached locally.
			-- Cancel the transfer.
			print ("GLib.Resources : Resource " .. namespace .. "/" .. id .. " found in local cache, cancelling resource download.")
			return false
		end
	end
)

timer.Create ("GLib.Resources.FlushCache", 60, 0,
	function ()
		for _, resource in pairs (GLib.Resources.Resources) do
			if resource:IsCachedInMemory () and
			   SysTime () - resource:GetLastAccessTime () > 60 then
				resource:ClearMemoryCache ()
			end
		end
	end
)