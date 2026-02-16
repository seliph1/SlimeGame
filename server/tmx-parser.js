// Conversor TMX (Tiled Map Editor) para JSON
// SEM DEPENDÊNCIAS - Parser XML puro em JavaScript

const fs = typeof require !== 'undefined' ? require('fs') : null;

class SimpleXMLParser {
    constructor() {
        this.pos = 0;
        this.text = '';
    }

    parse(xmlString) {
        this.text = xmlString.replace(/^[\ufeff\ufffe]/, ''); // Remove BOM
        this.text = this.text.replace(/<\?xml[^>]*\?>/g, ''); // Remove declaração
        this.pos = 0;
        
        return this.parseElement();
    }

    parseElement() {
        this.skipWhitespace();
        
        if (this.text[this.pos] !== '<') {
            return null;
        }
        
        this.pos++; // Pula '<'
        
        // Comentário
        if (this.text.substr(this.pos, 3) === '!--') {
            this.pos += 3;
            const end = this.text.indexOf('-->', this.pos);
            this.pos = end + 3;
            return this.parseElement();
        }
        
        // CDATA
        if (this.text.substr(this.pos, 8) === '![CDATA[') {
            this.pos += 8;
            const end = this.text.indexOf(']]>', this.pos);
            const content = this.text.substring(this.pos, end);
            this.pos = end + 3;
            return content;
        }
        
        // Tag
        const tagMatch = this.text.substr(this.pos).match(/^([a-zA-Z0-9:_-]+)/);
        if (!tagMatch) return null;
        
        const tagName = tagMatch[1];
        this.pos += tagName.length;
        
        // Atributos
        const attributes = {};
        while (true) {
            this.skipWhitespace();
            
            if (this.text[this.pos] === '/' || this.text[this.pos] === '>') {
                break;
            }
            
            const attrMatch = this.text.substr(this.pos).match(/^([a-zA-Z0-9:_-]+)\s*=\s*["']([^"']*)["']/);
            if (!attrMatch) break;
            
            attributes[attrMatch[1]] = this.decodeEntities(attrMatch[2]);
            this.pos += attrMatch[0].length;
        }
        
        // Self-closing tag
        if (this.text[this.pos] === '/') {
            this.pos += 2; // Pula '/>'
            return {
                tag: tagName,
                attributes: attributes,
                children: [],
                text: ''
            };
        }
        
        this.pos++; // Pula '>'
        
        // Conteúdo e filhos
        const children = [];
        let text = '';
        
        while (true) {
            this.skipWhitespace();
            
            // Fim da tag
            if (this.text.substr(this.pos, 2 + tagName.length) === '</' + tagName) {
                this.pos += 2 + tagName.length;
                this.skipWhitespace();
                this.pos++; // Pula '>'
                break;
            }
            
            // Nova tag filho
            if (this.text[this.pos] === '<') {
                const child = this.parseElement();
                if (child) {
                    if (typeof child === 'string') {
                        text += child;
                    } else {
                        children.push(child);
                    }
                }
            } else {
                // Texto
                const textEnd = this.text.indexOf('<', this.pos);
                if (textEnd === -1) break;
                
                text += this.text.substring(this.pos, textEnd);
                this.pos = textEnd;
            }
        }
        
        return {
            tag: tagName,
            attributes: attributes,
            children: children,
            text: this.decodeEntities(text.trim())
        };
    }

    skipWhitespace() {
        while (this.pos < this.text.length && /\s/.test(this.text[this.pos])) {
            this.pos++;
        }
    }

    decodeEntities(str) {
        return str
            .replace(/&lt;/g, '<')
            .replace(/&gt;/g, '>')
            .replace(/&amp;/g, '&')
            .replace(/&quot;/g, '"')
            .replace(/&apos;/g, "'")
            .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(n))
            .replace(/&#x([0-9a-fA-F]+);/g, (_, n) => String.fromCharCode(parseInt(n, 16)));
    }
}

class TMXParser {
    constructor() {
        this.xmlParser = new SimpleXMLParser();
    }

    // Encontra elemento filho por tag
    findChild(element, tagName) {
        if (!element.children) return null;
        return element.children.find(child => child.tag === tagName);
    }

    // Encontra todos elementos filhos por tag
    findChildren(element, tagName) {
        if (!element.children) return [];
        return element.children.filter(child => child.tag === tagName);
    }

    // Parse propriedades customizadas
    parseProperties(element) {
        const props = {};
        const propertiesEl = this.findChild(element, 'properties');
        
        if (propertiesEl) {
            const propertyEls = this.findChildren(propertiesEl, 'property');
            
            propertyEls.forEach(prop => {
                const name = prop.attributes.name;
                let value = prop.attributes.value || prop.text;
                const type = prop.attributes.type || 'string';
                
                if (type === 'int' || type === 'float') {
                    value = Number(value);
                } else if (type === 'bool') {
                    value = value === 'true';
                }
                
                props[name] = value;
            });
        }
        
        return props;
    }

    // Parse dados de layer (CSV ou XML)
    parseLayerData(dataEl, width, height) {
        const tiles = [];
        const encoding = dataEl.attributes.encoding;
        
        if (encoding === 'csv') {
            const csvData = dataEl.text.trim();
            const values = csvData.split(',').map(v => parseInt(v.trim()));
            tiles.push(...values);
        } else if (encoding === 'base64') {
            const base64Data = dataEl.text.trim();
            
            // Decodifica base64 sem dependências
            if (typeof Buffer !== 'undefined') {
                // Node.js
                const buffer = Buffer.from(base64Data, 'base64');
                for (let i = 0; i < buffer.length; i += 4) {
                    tiles.push(buffer.readUInt32LE(i));
                }
            } else {
                // Browser
                const binary = atob(base64Data);
                const bytes = new Uint8Array(binary.length);
                for (let i = 0; i < binary.length; i++) {
                    bytes[i] = binary.charCodeAt(i);
                }
                
                const view = new DataView(bytes.buffer);
                for (let i = 0; i < bytes.length; i += 4) {
                    tiles.push(view.getUint32(i, true)); // true = little-endian
                }
            }
        } else {
            // XML format
            const tileEls = this.findChildren(dataEl, 'tile');
            tileEls.forEach(tile => {
                tiles.push(parseInt(tile.attributes.gid || 0));
            });
        }
        
        // Converte para 2D
        const tileGrid = [];
        for (let y = 0; y < height; y++) {
            tileGrid[y] = [];
            for (let x = 0; x < width; x++) {
                tileGrid[y][x] = tiles[y * width + x] || 0;
            }
        }
        
        return tileGrid;
    }

    // Parse objetos
    parseObjects(objectGroupEl) {
        const objects = [];
        const objectEls = this.findChildren(objectGroupEl, 'object');
        
        objectEls.forEach(objEl => {
            const obj = {
                id: parseInt(objEl.attributes.id),
                name: objEl.attributes.name || '',
                type: objEl.attributes.type || objEl.attributes.class || '',
                x: parseFloat(objEl.attributes.x),
                y: parseFloat(objEl.attributes.y),
                width: parseFloat(objEl.attributes.width || 0),
                height: parseFloat(objEl.attributes.height || 0),
                rotation: parseFloat(objEl.attributes.rotation || 0),
                gid: objEl.attributes.gid ? parseInt(objEl.attributes.gid) : undefined,
                visible: objEl.attributes.visible !== '0',
                properties: this.parseProperties(objEl)
            };
            
            // Formas
            if (this.findChild(objEl, 'ellipse')) {
                obj.shape = 'ellipse';
            } else if (this.findChild(objEl, 'point')) {
                obj.shape = 'point';
            } else if (this.findChild(objEl, 'polygon')) {
                obj.shape = 'polygon';
                const pointsStr = this.findChild(objEl, 'polygon').attributes.points;
                obj.points = pointsStr.split(' ').map(p => {
                    const [x, y] = p.split(',').map(Number);
                    return { x, y };
                });
            } else if (this.findChild(objEl, 'polyline')) {
                obj.shape = 'polyline';
                const pointsStr = this.findChild(objEl, 'polyline').attributes.points;
                obj.points = pointsStr.split(' ').map(p => {
                    const [x, y] = p.split(',').map(Number);
                    return { x, y };
                });
            } else {
                obj.shape = 'rectangle';
            }
            
            objects.push(obj);
        });
        
        return objects;
    }

    // Parse TMX
    parse(xmlString) {
        const doc = this.xmlParser.parse(xmlString);
       
        if (doc.tag !== 'map') {
            throw new Error('XML não é um arquivo TMX válido');
        }
        
        const mapEl = doc;
        const map = {
            version: mapEl.attributes.version,
            tiledversion: mapEl.attributes.tiledversion,
            orientation: mapEl.attributes.orientation || 'orthogonal',
            renderorder: mapEl.attributes.renderorder || 'right-down',
            width: parseInt(mapEl.attributes.width),
            height: parseInt(mapEl.attributes.height),
            tilewidth: parseInt(mapEl.attributes.tilewidth),
            tileheight: parseInt(mapEl.attributes.tileheight),
            infinite: mapEl.attributes.infinite === '1',
            nextlayerid: parseInt(mapEl.attributes.nextlayerid || 0),
            nextobjectid: parseInt(mapEl.attributes.nextobjectid || 0),
            backgroundcolor: mapEl.attributes.backgroundcolor,
            properties: this.parseProperties(mapEl),
            tilesets: [],
            layers: []
        };
        
        // Tilesets
        const tilesetEls = this.findChildren(mapEl, 'tileset');
        tilesetEls.forEach(tsEl => {
            const tileset = {
                firstgid: parseInt(tsEl.attributes.firstgid),
                name: tsEl.attributes.name,
                tilewidth: parseInt(tsEl.attributes.tilewidth),
                tileheight: parseInt(tsEl.attributes.tileheight),
                tilecount: parseInt(tsEl.attributes.tilecount || 0),
                columns: parseInt(tsEl.attributes.columns || 0),
                spacing: parseInt(tsEl.attributes.spacing || 0),
                margin: parseInt(tsEl.attributes.margin || 0),
                source: tsEl.attributes.source,
                tiles: {}
            };
            
            // Image
            const imageEl = this.findChild(tsEl, 'image');
            if (imageEl) {
                tileset.image = {
                    source: imageEl.attributes.source,
                    width: parseInt(imageEl.attributes.width),
                    height: parseInt(imageEl.attributes.height),
                    trans: imageEl.attributes.trans
                };
            }
            
            // Tiles com propriedades
            const tileEls = this.findChildren(tsEl, 'tile');
            tileEls.forEach(tileEl => {
                const tileId = parseInt(tileEl.attributes.id);
                const tile = {
                    id: tileId,
                    type: tileEl.attributes.type || tileEl.attributes.class,
                    properties: this.parseProperties(tileEl)
                };
                
                // Animação
                const animationEl = this.findChild(tileEl, 'animation');
                if (animationEl) {
                    tile.animation = [];
                    const frameEls = this.findChildren(animationEl, 'frame');
                    frameEls.forEach(frame => {
                        tile.animation.push({
                            tileid: parseInt(frame.attributes.tileid),
                            duration: parseInt(frame.attributes.duration)
                        });
                    });
                }
                
                // Collision
                const objectGroupEl = this.findChild(tileEl, 'objectgroup');
                if (objectGroupEl) {
                    tile.objectGroup = {
                        objects: this.parseObjects(objectGroupEl)
                    };
                }
                
                tileset.tiles[tileId] = tile;
            });
            
            map.tilesets.push(tileset);
        });
        
        // Layers
        const layerEls = this.findChildren(mapEl, 'layer');
        layerEls.forEach(layerEl => {
            const layer = {
                type: 'tilelayer',
                id: parseInt(layerEl.attributes.id),
                name: layerEl.attributes.name,
                width: parseInt(layerEl.attributes.width),
                height: parseInt(layerEl.attributes.height),
                visible: layerEl.attributes.visible !== '0',
                opacity: parseFloat(layerEl.attributes.opacity || 1),
                offsetx: parseFloat(layerEl.attributes.offsetx || 0),
                offsety: parseFloat(layerEl.attributes.offsety || 0),
                properties: this.parseProperties(layerEl),
                data: null
            };
            
            const dataEl = this.findChild(layerEl, 'data');
            if (dataEl) {
                layer.data = this.parseLayerData(dataEl, layer.width, layer.height);
                layer.encoding = dataEl.attributes.encoding || 'xml';
            }
            
            map.layers.push(layer);
        });
        
        // Object groups
        const objGroupEls = this.findChildren(mapEl, 'objectgroup');
        objGroupEls.forEach(objGroupEl => {
            const objGroup = {
                type: 'objectgroup',
                id: parseInt(objGroupEl.attributes.id),
                name: objGroupEl.attributes.name,
                visible: objGroupEl.attributes.visible !== '0',
                opacity: parseFloat(objGroupEl.attributes.opacity || 1),
                offsetx: parseFloat(objGroupEl.attributes.offsetx || 0),
                offsety: parseFloat(objGroupEl.attributes.offsety || 0),
                draworder: objGroupEl.attributes.draworder || 'topdown',
                properties: this.parseProperties(objGroupEl),
                objects: this.parseObjects(objGroupEl)
            };
            
            map.layers.push(objGroup);
        });
        
        return map;
    }

    // Carrega arquivo (Node.js)
    loadFile(filename) {
        if (!fs) {
            throw new Error('loadFile só funciona no Node.js');
        }
        
        const xmlContent = fs.readFileSync(filename, 'utf8');
        return this.parse(xmlContent);
    }

    // Salva JSON (Node.js)
    saveJSON(map, filename) {
        if (!fs) {
            throw new Error('saveJSON só funciona no Node.js');
        }
        
        fs.writeFileSync(filename, JSON.stringify(map, null, 2), 'utf8');
    }
}

// Helper function
function TMXtoJSON(xmlStringOrFile, isFile = false) {
    const parser = new TMXParser();
    
    if (isFile) {
        return parser.loadFile(xmlStringOrFile);
    } else {
        return parser.parse(xmlStringOrFile);
    }
}

// Export
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { TMXParser, TMXtoJSON };
}

if (typeof window !== 'undefined') {
    window.TMXParser = TMXParser;
    window.TMXtoJSON = TMXtoJSON;
}