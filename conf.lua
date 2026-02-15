---@diagnostic disable: undefined-field
local arguments = love.arg.parseGameArguments(arg)
local initializer = {
   	server = function(t)
        t.title = "SlimeGame Server"
        t.author = "Gabriel Mendes (seliph1)"
        --t.console = true
        t.modules.graphics = false
        t.modules.sound = false
        t.modules.audio = false
        t.modules.video = false
        t.modules.window = false
        t.window = false
        t.vsync = false
        t.physics = false
	end,

    client = function(t)
        t.title = "SlimeGame Client"
        t.author = "Gabriel Mendes (seliph1)"
	end,
}

if arguments and type(arguments) == "table" then
    for index, argument in pairs(arguments) do
        if initializer[argument] then
            love.conf = initializer[argument]
        end
    end
end