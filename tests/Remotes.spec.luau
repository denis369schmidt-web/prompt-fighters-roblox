local Remotes = require(Shared.Net.Remotes)

describe("Remotes", function()
	it("rate-limits and validates every client-to-server remote", function()
		for name, def in Remotes do
			if def.direction == "toServer" then
				assert(def.perSecond and def.perSecond > 0, `{name} has no rate limit`)
				assert(def.args, `{name} has no argument schema`)
			end
		end
	end)
end)
