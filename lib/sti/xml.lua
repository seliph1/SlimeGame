-- Conversor TMX para formato STI (Simple Tiled Implementation)
-- Permite usar arquivos .tmx diretamente com STI

local sti_loader = {}

-- Parser XML básico
local function parse_xml(xml_string)
    local stack = {}
    local top = {tag = "root", attrs = {}, children = {}}
    local current = top
    
    xml_string = xml_string:gsub("^[\239\187\191]", "")
    xml_string = xml_string:gsub("^%s*<%?xml.-%?>", "")
    
    local i = 1
    while i <= #xml_string do
        if xml_string:sub(i, i) == "<" then
            if xml_string:sub(i, i + 3) == "<!--" then
                i = (xml_string:find("-->", i + 4, true) or #xml_string) + 3
            elseif xml_string:sub(i + 1, i + 1) == "/" then
                current = table.remove(stack)
                i = xml_string:find(">", i + 2, true) + 1
            else
                local tag_end = xml_string:find(">", i + 1, true)
                local tag_content = xml_string:sub(i + 1, tag_end - 1)
                local is_self_closing = tag_content:sub(-1) == "/"
                
                if is_self_closing then tag_content = tag_content:sub(1, -2) end
                
                local tag_name, attr_string = tag_content:match("^([%w:_-]+)%s*(.*)")
                local attrs = {}
                
                if attr_string then
                    for name, value in attr_string:gmatch('([%w:_-]+)%s*=%s*["\']([^"\']*)["\']') do
                        attrs[name] = value
                    end
                end
                
                local element = {tag = tag_name, attrs = attrs, children = {}, text = ""}
                table.insert(current.children, element)
                
                if not is_self_closing then
                    table.insert(stack, current)
                    current = element
                end
                
                i = tag_end + 1
            end
        else
            local text_end = xml_string:find("<", i, true) or (#xml_string + 1)
            local text = xml_string:sub(i, text_end - 1):match("^%s*(.-)%s*$")
            if text ~= "" then current.text = current.text .. text end
            i = text_end
        end
    end
    
    return top.children[1]
end

local function find_child(element, tag_name)
    for _, child in ipairs(element.children) do
        if child.tag == tag_name then return child end
    end
end

local function find_children(element, tag_name)
    local results = {}
    for _, child in ipairs(element.children) do
        if child.tag == tag_name then table.insert(results, child) end
    end
    return results
end

-- Parse propriedades customizadas
local function parse_properties(element)
    local props = {}
    local properties_elem = find_child(element, "properties")
    
    if properties_elem then
        for _, prop in ipairs(find_children(properties_elem, "property")) do
            local name = prop.attrs.name
            local value = prop.attrs.value or prop.text
            local prop_type = prop.attrs.type or "string"
            
            if prop_type == "int" or prop_type == "float" then
                value = tonumber(value)
            elseif prop_type == "bool" then
                value = (value == "true")
            elseif prop_type == "file" then
                value = value
            end
            
            props[name] = value
        end
    end
    
    return props
end

-- Parse dados de layer (CSV ou XML)
local function parse_layer_data(data_elem, width, height)
    local tiles = {}
    local encoding = data_elem.attrs.encoding
    
    if encoding == "csv" then
        local csv_data = data_elem.text
        for value in csv_data:gmatch("[^,]+") do
            table.insert(tiles, tonumber(value:match("^%s*(.-)%s*$")))
        end
    else
        -- Formato XML
        for _, tile_elem in ipairs(find_children(data_elem, "tile")) do
            table.insert(tiles, tonumber(tile_elem.attrs.gid or 0))
        end
    end
    
    return tiles
end

-- Converte TMX para formato STI
function sti_loader.parse_tmx(xml_string)
    local root = parse_xml(xml_string)
    
    if root.tag ~= "map" then
        error("XML não é um arquivo TMX válido")
    end
    
    -- Estrutura base compatível com STI
    local map = {
        version = root.attrs.version,
        luaversion = "5.1",
        tiledversion = root.attrs.tiledversion,
        orientation = root.attrs.orientation or "orthogonal",
        renderorder = root.attrs.renderorder or "right-down",
        width = tonumber(root.attrs.width),
        height = tonumber(root.attrs.height),
        tilewidth = tonumber(root.attrs.tilewidth),
        tileheight = tonumber(root.attrs.tileheight),
        nextlayerid = tonumber(root.attrs.nextlayerid),
        nextobjectid = tonumber(root.attrs.nextobjectid),
        properties = {},
        tilesets = {},
        layers = {}
    }
    
    -- Parse propriedades do mapa
    map.properties = parse_properties(root)
    
    -- Parse tilesets
    for _, tileset_elem in ipairs(find_children(root, "tileset")) do
        local tileset = {
            name = tileset_elem.attrs.name,
            firstgid = tonumber(tileset_elem.attrs.firstgid),
            tilewidth = tonumber(tileset_elem.attrs.tilewidth),
            tileheight = tonumber(tileset_elem.attrs.tileheight),
            spacing = tonumber(tileset_elem.attrs.spacing or 0),
            margin = tonumber(tileset_elem.attrs.margin or 0),
            columns = tonumber(tileset_elem.attrs.columns),
            tilecount = tonumber(tileset_elem.attrs.tilecount),
            tiles = {}
        }
        
        -- Image info
        local image_elem = find_child(tileset_elem, "image")
        if image_elem then
            tileset.image = image_elem.attrs.source
            tileset.imagewidth = tonumber(image_elem.attrs.width)
            tileset.imageheight = tonumber(image_elem.attrs.height)
            tileset.transparentcolor = image_elem.attrs.trans
        end
        
        -- Tiles individuais com propriedades
        for _, tile_elem in ipairs(find_children(tileset_elem, "tile")) do
            local tile_id = tonumber(tile_elem.attrs.id)
            local tile = {
                id = tile_id,
                properties = parse_properties(tile_elem)
            }
            
            -- Tipo do tile (class no Tiled 1.9+)
            if tile_elem.attrs.type or tile_elem.attrs.class then
                tile.type = tile_elem.attrs.type or tile_elem.attrs.class
            end
            
            -- Animação
            local animation_elem = find_child(tile_elem, "animation")
            if animation_elem then
                tile.animation = {}
                for _, frame in ipairs(find_children(animation_elem, "frame")) do
                    table.insert(tile.animation, {
                        tileid = tonumber(frame.attrs.tileid),
                        duration = tonumber(frame.attrs.duration)
                    })
                end
            end
            
            -- Collision objects (objectgroup)
            local objectgroup_elem = find_child(tile_elem, "objectgroup")
            if objectgroup_elem then
                tile.objectGroup = {
                    type = "objectgroup",
                    name = "",
                    visible = true,
                    opacity = 1,
                    offsetx = 0,
                    offsety = 0,
                    draworder = "index",
                    objects = {}
                }
                
                for _, obj_elem in ipairs(find_children(objectgroup_elem, "object")) do
                    table.insert(tile.objectGroup.objects, {
                        id = tonumber(obj_elem.attrs.id),
                        name = obj_elem.attrs.name or "",
                        type = obj_elem.attrs.type or "",
                        shape = find_child(obj_elem, "polygon") and "polygon" or "rectangle",
                        x = tonumber(obj_elem.attrs.x),
                        y = tonumber(obj_elem.attrs.y),
                        width = tonumber(obj_elem.attrs.width or 0),
                        height = tonumber(obj_elem.attrs.height or 0),
                        rotation = tonumber(obj_elem.attrs.rotation or 0),
                        visible = obj_elem.attrs.visible ~= "0",
                        properties = parse_properties(obj_elem)
                    })
                end
            end
            
			if tile_id then
            	tileset.tiles[tile_id] = tile
			end
        end
        
        table.insert(map.tilesets, tileset)
    end
    
    -- Parse layers
    for _, layer_elem in ipairs(find_children(root, "layer")) do
        local layer = {
            type = "tilelayer",
            id = tonumber(layer_elem.attrs.id),
            name = layer_elem.attrs.name,
            x = tonumber(layer_elem.attrs.x or 0),
            y = tonumber(layer_elem.attrs.y or 0),
            width = tonumber(layer_elem.attrs.width),
            height = tonumber(layer_elem.attrs.height),
            visible = layer_elem.attrs.visible ~= "0",
            opacity = tonumber(layer_elem.attrs.opacity or 1),
            offsetx = tonumber(layer_elem.attrs.offsetx or 0),
            offsety = tonumber(layer_elem.attrs.offsety or 0),
            properties = parse_properties(layer_elem),
            encoding = "lua", -- STI espera "lua" para arrays
            data = {}
        }
        
        -- Parse data
        local data_elem = find_child(layer_elem, "data")
        if data_elem then
            layer.data = parse_layer_data(data_elem, layer.width, layer.height)
        end
        
        table.insert(map.layers, layer)
    end
    
    -- Parse object groups
    for _, objgroup_elem in ipairs(find_children(root, "objectgroup")) do
        local objgroup = {
            type = "objectgroup",
            id = tonumber(objgroup_elem.attrs.id),
            name = objgroup_elem.attrs.name,
            visible = objgroup_elem.attrs.visible ~= "0",
            opacity = tonumber(objgroup_elem.attrs.opacity or 1),
            offsetx = tonumber(objgroup_elem.attrs.offsetx or 0),
            offsety = tonumber(objgroup_elem.attrs.offsety or 0),
            draworder = objgroup_elem.attrs.draworder or "topdown",
            properties = parse_properties(objgroup_elem),
            objects = {}
        }
        
        for _, obj_elem in ipairs(find_children(objgroup_elem, "object")) do
            local obj = {
                id = tonumber(obj_elem.attrs.id),
                name = obj_elem.attrs.name or "",
                type = obj_elem.attrs.type or obj_elem.attrs.class or "",
                shape = "rectangle",
                x = tonumber(obj_elem.attrs.x),
                y = tonumber(obj_elem.attrs.y),
                width = tonumber(obj_elem.attrs.width or 0),
                height = tonumber(obj_elem.attrs.height or 0),
                rotation = tonumber(obj_elem.attrs.rotation or 0),
                gid = tonumber(obj_elem.attrs.gid),
                visible = obj_elem.attrs.visible ~= "0",
                properties = parse_properties(obj_elem)
            }
            
            -- Formas especiais
            if find_child(obj_elem, "ellipse") then
                obj.shape = "ellipse"
            elseif find_child(obj_elem, "point") then
                obj.shape = "point"
            elseif find_child(obj_elem, "polygon") then
                obj.shape = "polygon"
                obj.polygon = {}
                local points_str = find_child(obj_elem, "polygon").attrs.points
                for point in points_str:gmatch("([^%s]+)") do
                    local x, y = point:match("([^,]+),([^,]+)")
                    table.insert(obj.polygon, {x = tonumber(x), y = tonumber(y)})
                end
            elseif find_child(obj_elem, "polyline") then
                obj.shape = "polyline"
                obj.polyline = {}
                local points_str = find_child(obj_elem, "polyline").attrs.points
                for point in points_str:gmatch("([^%s]+)") do
                    local x, y = point:match("([^,]+),([^,]+)")
                    table.insert(obj.polyline, {x = tonumber(x), y = tonumber(y)})
                end
            end
            
            table.insert(objgroup.objects, obj)
        end
        
        table.insert(map.layers, objgroup)
    end
    
    return map
end

-- Carrega arquivo TMX
function sti_loader.load_tmx(filename)
    local file = io.open(filename, "r")
    if not file then
        error("Não foi possível abrir o arquivo: " .. filename)
    end
    
    local xml_content = file:read("*all")
    file:close()
    
    return sti_loader.parse_tmx(xml_content)
end

function sti_loader:load(filename)
    return sti_loader.load_tmx(filename)
end

--[[
-- Wrapper para STI: permite usar .tmx ou .lua
function sti_loader.new_sti_loader(original_sti)
    local sti = original_sti or require("sti")
    local original_call = sti.__call
    
    -- Intercepta chamadas ao STI
    sti.__call = function(_, map, plugins, ox, oy)
        -- Se for string, verifica extensão
        if type(map) == "string" then
            local ext = map:sub(-4):lower()
            
            if ext == ".tmx" or ext == ".xml" then
                -- Carrega TMX e converte para formato STI
                map = sti_loader.load_tmx(map)
            end
        end
        
        -- Chama o STI original
        return original_call(_, map, plugins, ox, oy)
    end
    
    return sti
end
]]

setmetatable(sti_loader, {__call = sti_loader.load})

return sti_loader