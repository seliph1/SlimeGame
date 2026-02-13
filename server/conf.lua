
function love.conf(t)
    t.title = "TS2D Server"		-- The title of the window the game is in (string)
    t.author = "mozilla"		-- The author of the game (string)
	
	t.console = false
	--do return end
	t.modules.graphics = false
	t.modules.sound = false
	t.modules.audio = false
	t.modules.video = false
	t.modules.window = false
	t.window = false
	t.vsync = false
	t.physics = false
end
