--!strict
-- Server-side gate for every client-to-server remote: argument types from Remotes.args and a token bucket
-- per player and remote (burst = one second of `perSecond`). Pure logic, so it runs under Lune too.

local Remotes = require(script.Parent.Remotes)

export type Guard = {
	defs: { [string]: Remotes.RemoteDef },
	buckets: { [number]: { [string]: { tokens: number, at: number } } },
	allow: (self: Guard, userId: number, name: string, now: number, args: { any }) -> boolean,
	forget: (self: Guard, userId: number) -> (),
}

local Guard = {}
Guard.__index = Guard

local MAX_STRING = 200
Guard.MAX_STRING = MAX_STRING

function Guard.new(defs: { [string]: Remotes.RemoteDef }?): Guard
	local self = setmetatable({ defs = defs or Remotes, buckets = {} }, Guard)
	return (self :: any) :: Guard
end

local function argsValid(schema: { string }, args: { any }, maxLength: number?): boolean
	if #args ~= #schema then
		return false
	end
	for i, kind in schema do
		local value = args[i]
		if type(value) ~= kind then
			return false
		end
		if kind == "number" and (value ~= value or value == math.huge or value == -math.huge) then
			return false
		end
		if kind == "string" then
			-- Bytes: a UTF-8 character takes up to 4, so remotes with a character limit allow that many.
			if #value > (if maxLength then math.max(MAX_STRING, maxLength * 4) else MAX_STRING) then
				return false
			end
			-- Text must be valid UTF-8 and within the remote's character limit.
			local chars = utf8.len(value)
			if chars == nil or (maxLength ~= nil and chars > maxLength) then
				return false
			end
		end
	end
	return true
end

function Guard.allow(self: Guard, userId: number, name: string, now: number, args: { any }): boolean
	local def = self.defs[name]
	if not def or def.direction ~= "toServer" or def.perSecond == nil or def.args == nil then
		return false
	end
	local perSecond = def.perSecond :: number
	if not argsValid(def.args :: { string }, args, def.maxLength) then
		return false
	end
	local perPlayer = self.buckets[userId]
	if not perPlayer then
		perPlayer = {}
		self.buckets[userId] = perPlayer
	end
	local capacity = math.max(perSecond, 1)
	local bucket = perPlayer[name]
	if not bucket then
		bucket = { tokens = capacity, at = now }
		perPlayer[name] = bucket
	end
	bucket.tokens = math.min(capacity, bucket.tokens + (now - bucket.at) * perSecond)
	bucket.at = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

function Guard.forget(self: Guard, userId: number)
	self.buckets[userId] = nil
end

return Guard
