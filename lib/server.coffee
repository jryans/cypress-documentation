express     = require 'express'
http        = require 'http'
fs          = require 'fs'
hbs         = require 'hbs'
_           = require 'underscore'
_.str       = require 'underscore.string'
Promise     = require 'bluebird'
idGenerator = require './id_generator.coffee'
Project     = require "./project.coffee"
Settings    = require './util/settings'

## currently not making use of event emitter
## but may do so soon
class Server #extends require('./logger')
  constructor: ->
    @app    = null
    @server = null
    @io     = null

  initialize: (projectRoot) ->
    @config = @getCypressJson(projectRoot)

  getCypressJson: (projectRoot) ->
    obj = Settings.readSync(projectRoot)

    if url = obj.baseUrl
      ## always strip trailing slashes
      obj.baseUrl = _.str.rtrim(url, "/")

    ## commandTimeout should be in the cypress.json file
    ## since it has a significant impact on the tests
    ## passing or failing

    _.defaults obj,
      commandTimeout: 4000
      port: 3000
      autoOpen: false
      projectRoot: projectRoot

    _.defaults obj,
      clientUrl: "http://localhost:#{obj.port}"

    _.defaults obj,
      idGeneratorPath: "#{obj.clientUrl}/id_generator"

  configureApplication: ->
    ## set the cypress config from the cypress.json file
    @app.set "cypress",     @config
    @app.set "port",        @config.port
    @app.set "view engine", "html"
    @app.engine "html",     hbs.__express

    @app.use require("cookie-parser")()
    @app.use require("compression")()
    @app.use require("morgan")("dev")
    @app.use require("body-parser").json()
    @app.use require('express-session')({
      secret: "marionette is cool"
      saveUninitialized: true
      resave: true
      name: "__cypress.sid"
    })

    ## serve static file from public when route is /eclectus
    ## this is to namespace the static eclectus files away from
    ## the real application by separating the root from the files
    @app.use "/eclectus", express.static(__dirname + "/public")

    ## errorhandler
    @app.use require("errorhandler")()

  open: ->
    @app       = global.app = express()
    @server    = http.createServer(app)
    @io        = require("socket.io")(@server, {path: "/__socket.io"})
    @project   = new Project(@config.projectRoot)

    @configureApplication()

    ## refactor this class
    socket = new (require("./socket"))(@io, @app)
    socket.startListening()

    require("./routes")(@app)

    new Promise (resolve, reject) =>
      @server.listen @config.port, =>
        @isListening = true
        console.log "Express server listening on port: #{@config.port}"

        @project.ensureProjectId().bind(@)
        ## open phantom if ids are true (which they are by default)
        .then(idGenerator.openPhantom)
        .then ->
          require('open')(@config.clientUrl) if @config.autoOpen
        .return(@config)
        .then(resolve)
        .catch(reject)

  close: ->
    new Promise (resolve) =>
      ## bail early we dont have a server or we're not
      ## currently listening
      return resolve() if not @server or not @isListening

      @server.close =>
        @isListening = false
        console.log "Express server closed!"
        resolve()

module.exports = (projectRoot) ->
  if not projectRoot
    throw new Error("Instantiating lib/server requires a projectRoot!")

  server = new Server()
  server.initialize(projectRoot)
  server

# Server = (config) ->
#   argv = minimist(process.argv.slice(2), boolean: true)

#   return Server

# module.exports = Server