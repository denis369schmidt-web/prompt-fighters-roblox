--!strict
-- Rules for the lobby leaderboards (pure, tested under Lune; Server/Leaderboard/LeaderboardService talks to the
-- OrderedDataStores): which boards exist, their store names (the weekly board gets a new store every Monday
-- 00:00 UTC), a player's scores from the profile, write throttling, refresh backoff and the board rotation.

local Leaderboards = {}

export type Board = { id: string, title: string, store: string?, unit: string }
export type Scores = { [string]: number }
export type Entry = { userId: number, value: number }

Leaderboards.BOARDS = {
	{ id = "weekly", title = "SIEGE DIESE WOCHE", unit = "" },
	{ id = "wins", title = "SIEGE GESAMT", unit = "" },
	{ id = "level", title = "HÖCHSTES LEVEL", unit = "LV " },
} :: { Board }

Leaderboards.REFRESH_SECONDS = 60 -- read every board this often
Leaderboards.ROTATE_SECONDS = 10 -- the lobby board shows the next board this often
Leaderboards.WRITE_SECONDS = 90 -- at most one write per player and board this often (pending scores wait)
Leaderboards.BACKOFF_MAX = 600 -- longest wait after failed reads
Leaderboards.ROWS = 8
Leaderboards.STORE_VERSION = "v1"

-- Weeks since 1970 that start on Monday 00:00 UTC (1 January 1970 was a Thursday).
function Leaderboards.weekKey(unixTime: number): number
	return math.floor((math.floor(unixTime / 86400) + 3) / 7)
end

-- OrderedDataStore name of a board (the weekly one is a new store each week, so it starts empty).
function Leaderboards.storeName(boardId: string, unixTime: number): string
	if boardId == "weekly" then
		return `LB_WeeklyWins_{Leaderboards.STORE_VERSION}_{Leaderboards.weekKey(unixTime)}`
	elseif boardId == "wins" then
		return `LB_Wins_{Leaderboards.STORE_VERSION}`
	end
	return `LB_Level_{Leaderboards.STORE_VERSION}`
end

-- The values a player puts on each board. weekWins only counts when it was earned this week.
function Leaderboards.scores(
	profile: { wins: number, level: number, weekKey: number, weekWins: number },
	unixTime: number
): Scores
	local week = Leaderboards.weekKey(unixTime)
	return {
		weekly = if profile.weekKey == week then profile.weekWins else 0,
		wins = profile.wins,
		level = profile.level,
	}
end

-- Which boards need a write: the value changed since the last write and the board's throttle has passed.
-- `last` is { [boardId] = { value, at } } from earlier writes. Zero scores are never written.
function Leaderboards.dueWrites(
	scores: Scores,
	last: { [string]: { value: number, at: number } },
	now: number
): { string }
	local due = {}
	for _, board in Leaderboards.BOARDS do
		local value = scores[board.id]
		local previous = last[board.id]
		if value and value > 0 and (previous == nil or previous.value ~= value) then
			if previous == nil or now - previous.at >= Leaderboards.WRITE_SECONDS then
				table.insert(due, board.id)
			end
		end
	end
	return due
end

-- Seconds until the next read after `failures` failed reads in a row (doubles, capped).
function Leaderboards.backoff(failures: number): number
	if failures <= 0 then
		return Leaderboards.REFRESH_SECONDS
	end
	return math.min(Leaderboards.BACKOFF_MAX, Leaderboards.REFRESH_SECONDS * 2 ^ math.min(failures, 10))
end

-- Board rows for LobbyBuilder.setLeaderboard: name from `names` (unknown = "…"), value with the board's unit.
function Leaderboards.rows(
	board: Board,
	entries: { Entry },
	names: { [number]: string }
): { { name: string, value: string } }
	local out = {}
	for i, entry in entries do
		if i > Leaderboards.ROWS then
			break
		end
		out[i] = { name = names[entry.userId] or "…", value = `{board.unit}{math.floor(entry.value)}` }
	end
	return out
end

-- Index of the board to show after `current` (1-based): the next one that has rows, or `current` if none.
function Leaderboards.nextBoard(current: number, hasRows: { [number]: boolean }): number
	local n = #Leaderboards.BOARDS
	for step = 1, n do
		local k = (current - 1 + step) % n + 1
		if hasRows[k] then
			return k
		end
	end
	return current
end

return Leaderboards
