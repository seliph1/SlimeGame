-- Client extension for CS lib
local serpent = require "lib.serpent"
local client = require "lib.cs"
local sti = require "lib.sti"
local xml = require "lib.sti.xml"
local anim8 = require "lib.anim8"


local slimeImage = love.graphics.newImage("assets/sprites/Slime1_Idle_full.png")
local imageWidth, imageHeight = slimeImage:getDimensions()
local grid = anim8.newGrid(64, 64, imageWidth, imageHeight, 0, 0, 0)
local slimeFrames = {
    ["down"] = anim8.newAnimation(grid('1-6', 1), 0.1 ),
    ["up"] = anim8.newAnimation(grid('1-6', 2), 0.1 ),
    ["left"] = anim8.newAnimation(grid('1-6', 3), 0.1 ),
    ["right"] = anim8.newAnimation(grid('1-6', 4), 0.1 ),
}


local map = sti( xml("map_projects/mapateste.tmx") )

map:addCustomLayer("Sprite Layer", 3)
local spriteLayer = map.layers["Sprite Layer"]
spriteLayer.sprites = {
    player = {
        x = 64,
        y = 64,
        r = 0,
        speed = 60,
        facing = "down",
        animationGrid = slimeFrames,
        image = slimeImage,
    }
}

function spriteLayer:draw()
    for index, sprite in pairs(self.sprites) do
        local x = math.floor(sprite.x)
        local y = math.floor(sprite.y)
        local r = sprite.r
        local facing = sprite.facing
        sprite.animationGrid[facing]:draw(sprite.image, x, y)
    end
end

function spriteLayer:update(dt)
    for index, sprite in pairs(self.sprites) do
        if love.keyboard.isDown("w") then
            sprite.y = sprite.y - sprite.speed * dt
            sprite.facing = "up"
        end
        if love.keyboard.isDown("a") then
            sprite.x = sprite.x - sprite.speed * dt
            sprite.facing = "left"
        end
        if love.keyboard.isDown("s") then
            sprite.y = sprite.y + sprite.speed * dt
            sprite.facing = "down"
        end
        if love.keyboard.isDown("d") then
            sprite.x = sprite.x + sprite.speed * dt
            sprite.facing = "right"
        end
        sprite.animationGrid[sprite.facing]:update(dt)
    end
end

function client.load()
    
end

function client.draw()
    map:draw()
end

function client.update( dt )
    client.preupdate(dt)

    map:update(dt)

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