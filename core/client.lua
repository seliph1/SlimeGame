-- Client extension for CS lib
local serpent = require "lib.serpent"
local client = require "lib.cs"
local STI = require "lib.sti"
local XML = require "lib.sti.xml"
local anim8 = require "lib.anim8"
local Bump = require "lib.bump"

local camera = require "lib.gamera".new(0, 0, 2000, 2000)
client.camera = camera

client.input = {}

--local map = STI( "maps/mapainfinto.lua", { "bump"} )
local map = STI( XML("maps/mapainfinto.tmx"), { "bump"} )
client.map = map

local world = Bump.newWorld(64)
client.world = world


map:bump_init(world)


local slimeImage = love.graphics.newImage("assets/sprites/Slime1_Idle_full.png")
local imageWidth, imageHeight = slimeImage:getDimensions()
local grid = anim8.newGrid(64, 64, imageWidth, imageHeight, 0, 0, 0)
local slimeFrames = {
    ["down"] = anim8.newAnimation(grid('1-6', 1), 0.1 ),
    ["up"] = anim8.newAnimation(grid('1-6', 2), 0.1 ),
    ["left"] = anim8.newAnimation(grid('1-6', 3), 0.1 ),
    ["right"] = anim8.newAnimation(grid('1-6', 4), 0.1 ),
}

--print(serpent.block(map.layers, {}))

local spriteLayer = map.layers["sprites"]
local collisionLayer = map.layers["collision"]
function collisionLayer:draw() end

function spriteLayer:draw()
    for index, sprite in pairs(self.objects) do
        if sprite.class == "Player" then
            local x = math.floor(sprite.x)
            local y = math.floor(sprite.y)
            local r = sprite.r
            local facing = sprite.facing
            sprite.animationGrid[facing]:draw(sprite.image, x, y)
        end

        if sprite.class == "Rectangle" then
            love.graphics.rectangle("fill", sprite.x, sprite.y, sprite.width, sprite.height)
        end
    end
end

function spriteLayer:update(dt)
    local v, h, w = client.getVectors()

    for index, sprite in pairs(self.objects) do
        if sprite.class == "Player" then
            if v~= 0 or h ~= 0 then
                -- Get player position and speed
                local speed = sprite.speed * dt
                local x, y = sprite.x, sprite.y
                local margin = sprite.margin
                -- Get the projected value from position + speed * direction
                local fx = x + speed * h * w
                local fy = y + speed * v * w

                -- Calculate player colliding with other objects
                local cx, cy, collisions, length = world:move(sprite, fx + margin, fy + margin)

                -- Update the position
                sprite.x = cx - margin
                sprite.y = cy - margin

                -- Update facing direction
                sprite.animationGrid[sprite.facing]:update(dt)
            end
        end
    end
end

function client.getArrowVectors()
    local h, v, w = 0, 0, 1
    local input = client.input
    if input["up"]     then v = -1 	 end
    if input["down"]   then v =  1 	 end
    if input["left"]   then h = -1 	 end
    if input["right"]  then h =  1 	 end
    if input["lshift"] then w =  0.5 end

    if v ~= 0 or h ~= 0 then
        local mag = math.sqrt(v*v + h*h)
        local scale
        if mag == 0 then
            v, h = 0, 0
        else
            scale = 1/mag
            v, h = v * scale, h * scale
        end
    end
    return v, h, w
end

function client.getVectors()
    local h, v, w = 0, 0, 1
    local input = client.input
    if input["w"]       then v = -1 	end
    if input["s"] 	    then v =  1 	end
    if input["a"] 	    then h = -1 	end
    if input["d"] 	    then h =  1 	end
    if input["lshift"] 	then w =  0.5 	end

    if v ~= 0 or h ~= 0 then
        local mag = math.sqrt(v*v + h*h)
        local scale
        if mag == 0 then
            v, h = 0, 0
        else
            scale = 1/mag
            v, h = v * scale, h * scale
        end
    end
    return v, h, w
end

function client.spawnPlayer(x, y, margin)
    x = x or 64
    y = y or 64
    margin = margin or 0
    local spriteLayer = map.layers["sprites"]
    local player = {
        x = x,
        y = y,
        r = 0,
        speed = 120,
        class = "Player",
        facing = "down",
        animationGrid = slimeFrames,
        image = slimeImage,
        margin = margin
    }
    table.insert(spriteLayer.objects, player)
    world:add(player, player.x + margin, player.y + margin, 64 - margin*2, 64 - margin*2)
end
client.spawnPlayer(32, 32, 24)

function client.viewport(l, t, w, h)
    map:draw(-l, -t)
    --map:bump_draw()
end

function client.draw()
    --//=-=-=-=-=-=-=-=-=-=-=-=//--
    camera:draw(client.viewport)
    --//=-=-=-=-=-=-=-=-=-=-=-=//--
end

camera.speed = 60
function camera:update(dt)
    local s = camera.speed * dt
    local v, h = client.getArrowVectors()

    local dx, dy = h * s, v * s

    if v ~= 0 or h ~= 0 then
        self:increasePosition(dx, dy)
    end
end

function client.update( dt )
    client.preupdate(dt)
    --//=-=-=-=-=-=-=-=-=-=-=-=//--
    map:update(dt)
    camera:update(dt)
    --//=-=-=-=-=-=-=-=-=-=-=-=//--
    client.postupdate(dt)
end

function client.keypressed(key)
    client.input[key] = true
end

function client.keyreleased(key)
    client.input[key] = false
end

function client.mousemoved(x, y, dx, dy, istouch)
end

function client.mousepressed(x, y, button, istouch, presses)
end

function client.mousereleased(x, y, button, istouch, presses)
end

function client.wheelmoved(x, y)
end

function client.load()
end

return client