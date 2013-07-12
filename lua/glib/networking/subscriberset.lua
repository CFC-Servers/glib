local self = {}
GLib.SubscriberSet = GLib.MakeConstructor (self)

--[[
	Cleared ()
		Fired when this SubscriberSet has been cleared.
	PlayerAdded (Player ply)
		Fired when a player has been added to this SubscriberSet.
	PlayerRemoved (Player ply)
		Fired when a player has been removed from this SubscriberSet.
]]

function self:ctor ()
	self.PlayerSet = {}
	self.Players = {}
	
	GLib.EventProvider (self)
end

function self:AddPlayer (ply)
	if self.PlayerSet [ply] then return end
		self.PlayerSet [ply] = self.PlayerSet [ply] + 1
	else
		self.Players [#self.Players + 1] = ply
		self.PlayerSet [ply] = 1
		
		self:DispatchEvent ("PlayerAdded", ply)
	end
end

function self:Clear ()
	self.PlayerSet = {}
	self.Players = {}
	
	self:DispatchEvent ("Cleared")
end

function self:ContainsPlayer (ply)
	return self.PlayerSet [ply] and true or false
end

function self:ContainsUser (userId)
	for i = 1, #self.Players do
		if self.Players [i]:IsValid () and
		   GLib.GetPlayerId (self.Players [i]) == userId then
			return true
		end
	end
	return false
end

function self:GetPlayerEnumerator ()
	self:CleanUp ()
	
	local i = 0
	return function ()
		i = i + 1
		return self.Players [i]
	end
end

function self:GetRecipientFilter ()
	self:CleanUp ()
	return self.Players
end

function self:IsEmpty ()
	self:CleanUp ()
	return #self.Players == 0
end

function self:RemovePlayer (ply)
	if not self.PlayerSet [ply] then return end
	
	self.PlayerSet [ply] = self.PlayerSet [ply] - 1
	if self.PlayerSet [ply] > 0 then return end
	
	self.PlayerSet [ply] = nil
	for i = 1, #self.Players do
		if self.Players [i] == ply then
			table.remove (self.Players, i)
			break
		end
	end
	
	self:DispatchEvent ("PlayerRemoved", ply)
end

function self:ToString ()
	local subscriberSet = ""
	
	for ply in self:GetPlayerEnumerator () do
		if subscriberSet ~= "" then
			subscriberSet = subscriberSet .. ", "
		end
		subscriberSet = subscriberSet .. GLib.GetPlayerId (ply) .. " (" .. ply:Name () .. ")"
	end
	
	subscriberSet = "{" .. subscriberSet .. "}"
	return subscriberSet
end

self.__tostring = self.ToString

-- Internal, do not call
function self:CleanUp ()
	for i = #self.Players, 1, -1 do
		if not self.Players [i]:IsValid () then
			self:DispatchEvent ("PlayerRemoved", self.Players [i])
			self.PlayerSet [self.Players [i]] = nil
			table.remove (self.Players, i)
		end
	end
end