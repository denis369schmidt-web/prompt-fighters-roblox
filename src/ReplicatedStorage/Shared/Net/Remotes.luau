--!strict
-- Remote definitions. Clients send inputs and requests only; the server validates every argument
-- against `args` and drops calls above `perSecond`. Purchases and rewards never run on the client.

export type RemoteDef = {
	kind: "event" | "function",
	direction: "toServer" | "toClient",
	perSecond: number?,
	args: { string }?,
}

local Remotes: { [string]: RemoteDef } = {
	-- 60 Hz input: bitmask, stick x, stick y, sequence number.
	Input = {
		kind = "event",
		direction = "toServer",
		perSecond = 75,
		args = { "number", "number", "number", "number" },
	},
	Snapshot = { kind = "event", direction = "toClient" },
	MatchEvent = { kind = "event", direction = "toClient" },
	-- Projectile positions at 30 Hz (unreliable), spawned and ended through MatchEvent.
	Shots = { kind = "event", direction = "toClient" },
	FinisherCode = { kind = "event", direction = "toServer", perSecond = 10, args = { "string" } },
	SelectFighter = { kind = "event", direction = "toServer", perSecond = 4, args = { "string" } },
	VoteArena = { kind = "event", direction = "toServer", perSecond = 2, args = { "string" } },
	BuyWithCoins = { kind = "function", direction = "toServer", perSecond = 3, args = { "string", "string" } },
	SubmitPrompt = { kind = "function", direction = "toServer", perSecond = 0.5, args = { "string" } },
	ClaimReward = { kind = "function", direction = "toServer", perSecond = 2, args = { "string" } },
}

return Remotes
