-- Client extension for CS lib
local client = require "lib.cs"

function client.load()
end

function client.draw()
end

function client.update( dt )
    client.preupdate(dt)
	client.postupdate(dt)
end

function client.keypressed()
end

function client.keyreleased()
end

function client.mousemoved()
end

function client.mousepressed()
end

function client.mousereleased()
end

function client.wheelmoved()
end

return client