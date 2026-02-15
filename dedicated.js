//Entry point for SlimeGame dedicated ws server
const server = require ("./server/server.js")
const tiled = require ("./server/tiled.js")


server.disconnectCallback = function(peer_id) {
    console.log(peer_id + "disconnected")
}

server.connectCallback = function(peer_id) {
    console.log(peer_id + "connected")
}
