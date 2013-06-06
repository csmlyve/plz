nopt = require 'nopt'
path = require 'path'

logging = require("./logging")
plz = require("./plz")

longOptions =
  filename: [ path, null ]
  run: Boolean
  version: Boolean
  help: Boolean
  tasks: Boolean
  verbose: Boolean
  debug: Boolean
  "no-colors": Boolean
  colors: Boolean

shortOptions =
  f: [ "--filename" ]
  r: [ "--run" ]
  v: [ "--verbose" ]
  D: [ "--debug" ]

run = ->
  options = nopt(longOptions, shortOptions)

  if options.colors then logging.useColors(true)
  if options["no-colors"] then logging.useColors(false)
  if options.verbose then logging.setVerbose(true)
  if options.debug
    logging.setVerbose(true)
    logging.setDebug(true)
  if options.version
    console.log "plz #{plz.VERSION}"
    process.exit 0
  if options.help
    console.log(HELP)
  plz.run(options)

HELP = """
plz #{plz.VERSION}
usage: plz [options] (task-name [task-options])*

general options are listed below. task-options are all of the form
"<name>=<value>".

example:
  plz -f #{plz.DEFAULT_FILENAME} build debug=true run

  loads rules from #{plz.DEFAULT_FILENAME}, then runs two tasks:
    - "build", with options { debug: true }
    - "run", with no options

options:
  --filename FILENAME (-f)
      use a specific rules file (default: #{plz.DEFAULT_FILENAME})
  --tasks
      show the list of tasks and their descriptions
  --run (-r)
      stay running, monitoring files for changes
  --help
      this help
  --version
      show the version string and exit
  --verbose (-v)
      log more about what it's doing
  --debug (-D)
      log quite a lot more about what it's thinking
  --colors / --no-colors
      override the color detection to turn on/off terminal colors

"""

exports.run = run