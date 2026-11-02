-- Retention features: leaderboard rules (Meta/Leaderboards) and the profile fields they use (weekly wins,
-- group bonus, settings).
local Constants = require(Shared.Data.Constants)
local Leaderboards = require(Shared.Meta.Leaderboards)
local Profile = require(Shared.Meta.Profile)

-- Monday 2 November 2026, 00:00 UTC and one second before it (Sunday).
local MONDAY = 1793577600
local SUNDAY = MONDAY - 1

describe("Leaderboards", function()
	it("starts a new week on Monday 00:00 UTC", function()
		expect(Leaderboards.weekKey(MONDAY)).toBe(Leaderboards.weekKey(SUNDAY) + 1)
		expect(Leaderboards.weekKey(MONDAY + 6 * 86400 + 86399)).toBe(Leaderboards.weekKey(MONDAY))
		expect(Leaderboards.storeName("weekly", MONDAY)).never.toBe(Leaderboards.storeName("weekly", SUNDAY))
		expect(Leaderboards.storeName("wins", MONDAY)).toBe(Leaderboards.storeName("wins", SUNDAY))
	end)

	it("only counts weekly wins of the current week", function()
		local p = Profile.new()
		p.wins, p.level = 12, 7
		Profile.addWeeklyWin(p, Leaderboards.weekKey(SUNDAY))
		Profile.addWeeklyWin(p, Leaderboards.weekKey(SUNDAY))
		expect(Leaderboards.scores(p, SUNDAY).weekly).toBe(2)
		expect(Leaderboards.scores(p, MONDAY).weekly).toBe(0)
		expect(Leaderboards.scores(p, MONDAY).wins).toBe(12)
		expect(Leaderboards.scores(p, MONDAY).level).toBe(7)
		Profile.addWeeklyWin(p, Leaderboards.weekKey(MONDAY))
		expect(p.weekWins).toBe(1)
	end)

	it("throttles writes per board and skips unchanged and zero scores", function()
		local scores = { weekly = 0, wins = 3, level = 2 }
		local due = Leaderboards.dueWrites(scores, {}, 100)
		expect(table.find(due, "weekly")).toBe(nil)
		expect(#due).toBe(2)
		local last = { wins = { value = 3, at = 100 }, level = { value = 1, at = 100 } }
		expect(#Leaderboards.dueWrites(scores, last, 110)).toBe(0) -- level changed but throttled
		local later = Leaderboards.dueWrites(scores, last, 100 + Leaderboards.WRITE_SECONDS)
		expect(#later).toBe(1)
		expect(later[1]).toBe("level")
	end)

	it("backs off after failed reads, capped", function()
		expect(Leaderboards.backoff(0)).toBe(Leaderboards.REFRESH_SECONDS)
		expect(Leaderboards.backoff(1)).toBeGreaterThan(Leaderboards.REFRESH_SECONDS)
		expect(Leaderboards.backoff(50)).toBe(Leaderboards.BACKOFF_MAX)
	end)

	it("builds board rows with names and units, at most ROWS", function()
		local entries = {}
		for i = 1, 12 do
			entries[i] = { userId = i, value = 20 - i }
		end
		local rows = Leaderboards.rows(Leaderboards.BOARDS[3], entries, { [1] = "Ada" })
		expect(#rows).toBe(Leaderboards.ROWS)
		expect(rows[1].name).toBe("Ada")
		expect(rows[1].value).toBe("LV 19")
		expect(rows[2].name).toBe("…")
	end)

	it("rotates to the next board that has rows", function()
		expect(Leaderboards.nextBoard(1, { true, true, true })).toBe(2)
		expect(Leaderboards.nextBoard(3, { true, true, true })).toBe(1)
		expect(Leaderboards.nextBoard(1, { false, false, true })).toBe(3)
		expect(Leaderboards.nextBoard(2, {})).toBe(2)
	end)
end)

describe("Profile growth fields", function()
	it("pays the group bonus exactly once", function()
		local p = Profile.new()
		local before = p.coins
		expect(Profile.claimGroupBonus(p)).toBe(Constants.GROUP_BONUS_COINS)
		expect(Profile.claimGroupBonus(p)).toBe(0)
		expect(p.coins).toBe(before + Constants.GROUP_BONUS_COINS)
	end)

	it("saves known settings and refuses unknown keys or wrong types", function()
		local p = Profile.new()
		expect(p.settings.sound).toBe(true)
		expect(Profile.setSetting(p, "reduceShake", true)).toBe(true)
		expect(Profile.setSetting(p, "sound", "off")).toBe(false)
		expect(Profile.setSetting(p, "admin", true)).toBe(false)
		expect(p.settings.reduceShake).toBe(true)
		expect(Profile.view(p).settings.reduceShake).toBe(true)
	end)

	it("migrates old saves and repairs damaged settings", function()
		local old = { version = 2, coins = 500, wins = 4, level = 3 }
		local p = Profile.migrate(old)
		expect(p.coins).toBe(500)
		expect(p.groupBonus).toBe(false)
		expect(p.weekWins).toBe(0)
		expect(p.settings.sound).toBe(true)
		local damaged = Profile.migrate({ settings = { sound = false, reduceShake = "yes", evil = true } })
		expect(damaged.settings.sound).toBe(false)
		expect(damaged.settings.reduceShake).toBe(false)
		expect((damaged.settings :: any).evil).toBe(nil)
	end)
end)
