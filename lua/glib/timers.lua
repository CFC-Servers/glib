local delayedCalls = {}
GLib.SlowDelayedCalls = {}

function GLib.CallDelayed (callback, delay)
	if not callback then return end
	if type (callback) ~= "function" then
		GLib.Error ("GLib.CallDelayed : callback must be a function!")
		return
	end
	
	table.insert (delayedCalls, {callback, delay})
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
hook.Add ("Think", "GLib.DelayedCalls",
	function ()
		if paused then return end

		local func, delay
		local startTime = SysTime ()
		while SysTime () - startTime < 0.0025 and #delayedCalls > 0 do
			func, delay = unpack(table.remove(delayedCalls, 1))
			xpcall (func, GLib.Error)

			if delay then
				paused = true
				timer.Simple (delay, function()
					paused = false
				end )

				break
			end
		end
	end
)
