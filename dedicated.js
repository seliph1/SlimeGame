//Entry point for SlimeGame dedicated ws server
const server = require ("./server/server.js")
const {TMXParser} = require("./server/tmx-parser.js")

const parser = new TMXParser()
const map = parser.loadFile("map_projects/mapateste.tmx")



server.disconnectCallback = function(peer_id) {
    console.log(peer_id)
}

server.connectCallback = function(peer_id) {
    console.log(peer_id)
}
