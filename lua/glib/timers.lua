local delayedCalls = {}
GLib.SlowDelayedCalls = {}

function GLib.CallDelayed (callback)
	if not callback then return end
	if type (callback) ~= "function" then
		GLib.Error ("GLib.CallDelayed : callback must be a function!")
		return
	end
	
	table.insert (delayedCalls, callback)
end

function GLib.PolledWait (interval, timeout, predicate, callback)
	if not callback then return end
	if not predicate then return end
	
	if predicate () then
		callback ()
		return
	end
	
	if timeout < 0 then return end
	
	timer.Simple (interval,
		function ()
			GLib.PolledWait (interval, timeout - interval, predicate, callback)
		end
	)
end

local paused = false
local xpcall = xpcall
local SysTime = SysTime
local table_remove = table.remove
hook.Add ("Think", "GLib.DelayedCalls",
	function ()
		if paused then return end
		local GLibError = GLib.Error

		local startTime = SysTime ()
		while SysTime () - startTime < 0.0025 and #delayedCalls > 0 do
			local func = table_remove (delayedCalls, 1)
			xpcall (func, GLibError)
		end
	end
)
