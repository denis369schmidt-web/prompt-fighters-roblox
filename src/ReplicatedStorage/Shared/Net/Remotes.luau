--!strict
-- Remote definitions. Clients send inputs and requests only; the server validates every argument
-- against `args` and drops calls above `perSecond`. Purchases and rewards never run on the client.

export type RemoteDef = {
	kind: "event" | "function",
	direction: "toServer" | "toClient",
	perSecond: number?,
	args: { string }?,
	maxLength: number?, -- longest string argument in characters (default Guard.MAX_STRING bytes)
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
	-- Arena items at 10 Hz (unreliable): id, kind, position, holder.
	Items = { kind = "event", direction = "toClient" },
	-- Saved progress for the local player (coins, level, owned fighters) plus one-off news (reward, login bonus).
	Profile = { kind = "event", direction = "toClient" },
	BuyFighter = { kind = "event", direction = "toServer", perSecond = 2, args = { "string" } },
	FinisherCode = { kind = "event", direction = "toServer", perSecond = 10, args = { "string" } },
	SelectFighter = { kind = "event", direction = "toServer", perSecond = 4, args = { "string" } },
	VoteArena = { kind = "event", direction = "toServer", perSecond = 2, args = { "string" } },
	-- Results screen: true = NOCHMAL (same fighters and arena), false = Zur Lobby.
	VoteRematch = { kind = "event", direction = "toServer", perSecond = 2, args = { "boolean" } },
	BuyWithCoins = { kind = "function", direction = "toServer", perSecond = 3, args = { "string", "string" } },
	-- Prompt fighters: raw prompt text (filtered on the server before anything else) or a 6-character share code.
	-- Both answer { ok, message?, fighter? } (Prompt/Interpreter Summary).
	SubmitPrompt = { kind = "function", direction = "toServer", perSecond = 0.5, args = { "string" }, maxLength = 120 },
	LoadPromptCode = { kind = "function", direction = "toServer", perSecond = 1, args = { "string" }, maxLength = 16 },
	ClaimReward = { kind = "function", direction = "toServer", perSecond = 2, args = { "string" } },
	-- Settings panel: option key (Profile.Settings) and its new value.
	SaveSetting = { kind = "event", direction = "toServer", perSecond = 4, args = { "string", "boolean" } },
}

return Remotes
