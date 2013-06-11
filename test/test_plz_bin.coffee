fs = require 'fs'
minimatch = require 'minimatch'
path = require 'path'
Q = require 'q'
shell = require 'shelljs'
should = require 'should'
touch = require 'touch'
util = require 'util'

test_util = require("./test_util")
futureTest = test_util.futureTest
withTempFolder = test_util.withTempFolder
execFuture = test_util.execFuture

dump = (x) -> util.inspect x, false, null, true

binplz = "#{process.cwd()}/bin/plz"

#
# effectively integration tests.
# verify the behavior of 'bin/plz'.
#
describe "bin/plz", ->
  it "responds to --help", futureTest ->
    execFuture("#{binplz} --help").then (p) ->
      p.stderr.toString().should.eql("")
      p.stdout.toString().should.match /usage:/
      p.stdout.toString().should.match /options:/

  it "describes existing tasks in --help and --tasks", futureTest withTempFolder (folder) ->
    fs.writeFileSync "#{folder}/rules", "task 'xyzzy', desc: 'plover', run: ->\n"
    execFuture("#{binplz} -f rules --help")
    .then (p) ->
      p.stderr.toString().should.eql("")
      p.stdout.toString().should.match /xyzzy/
      p.stdout.toString().should.match /plover/
      execFuture("#{binplz} -f rules --tasks")
    .then (p) ->
      p.stdout.should.match(/Known tasks:\n  xyzzy - plover\n/)

  it "obeys --colors and --no-colors", futureTest withTempFolder (folder) ->
    fs.writeFileSync "#{folder}/rules", "task 'xyzzy', desc: 'plover', run: ->\n"
    execFuture("#{binplz} -D -f rules --color --help")
    .then (p) ->
      p.stdout.should.match(/\n\u001b\[32m\[\d\d\.\d\d\d] Defining task: xyzzy/)
      execFuture("#{binplz} -D -f rules --no-color --help")
    .then (p) ->
      p.stdout.should.match(/\n\[\d\d\.\d\d\d\] Defining task: xyzzy/)

  it "can do basic shell commands", futureTest withTempFolder (folder) ->
    fs.writeFileSync "#{folder}/rules", SHELL_TEST
    execFuture("#{binplz} -f rules wiggle")
    .then (p) ->
      p.stdout.should.match(/Warning: bumblebee cicada rules\n/)

  it "can attach a task before another one", futureTest withTempFolder (folder) ->
    fs.writeFileSync "#{folder}/rules", BEFORE_TEST
    execFuture("#{binplz} -f rules main")
    .then (p) ->
      p.stdout.should.match(/even worse.\nbarnacle.\nmain.\n/)

  it "can attach a task after another one", futureTest withTempFolder (folder) ->
    fs.writeFileSync "#{folder}/rules", AFTER_TEST
    execFuture("#{binplz} -f rules main")
    .then (p) ->
      p.stdout.should.match(/main.\nbarnacle.\neven worse.\n/)

  it "can attach tasks on both sides", futureTest withTempFolder (folder) ->
    fs.writeFileSync "#{folder}/rules", AROUND_TEST
    execFuture("#{binplz} -f rules --tasks")
    .then (p) ->
      p.stdout.should.match(/Known tasks:\n  main - plover\n\n/)
      execFuture("#{binplz} -f rules main")
    .then (p) ->
      p.stdout.should.match(/barnacle 1.\nmain.\nbarnacle 2.\n/)

  it "can execute lines sequentially", futureTest withTempFolder (folder) ->
    fs.writeFileSync "#{folder}/rules", EXEC_TEST
    execFuture("#{binplz} -f rules sleeper")
    .then (p) ->
      p.stdout.should.match(/hello\ngoodbye\n/)

  it "topo-sorts dependent tasks and runs each only once", futureTest withTempFolder (folder) ->
    fs.writeFileSync "#{folder}/rules", TOPO_TEST
    execFuture("#{binplz} -f rules pets")
    .then (p) ->
      p.stdout.should.match(/bee\ncat\ndog\npets!\nFinished/)
      execFuture("#{binplz} -f rules pets cat")
    .then (p) ->
      p.stdout.should.match(/bee\ncat\ndog\npets!\nFinished/)

  it "runs without exiting, waiting for file changes", futureTest withTempFolder (folder) ->
    fs.writeFileSync "#{folder}/rules", RUN_TEST.replace("%FOLDER%", folder)
    f1 = execFuture("#{binplz} -r -f rules main").then (p) ->
      p.stdout.should.match(/hello\ngoodbye\n/)
    f2 = Q.delay(500).then ->
      fs.writeFileSync "#{folder}/die.x", "die!"
    Q.all([ f1, f2 ])

  it "can get and set configs", futureTest withTempFolder (folder) ->
    fs.writeFileSync "#{folder}/rules", CONFIG_TEST
    execFuture("#{binplz} -f rules test").then (p) ->
      p.stdout.should.match(/ok!\ninfo 1\ndone\n/)

  it "can enqueue a task manually", futureTest withTempFolder (folder) ->
    fs.writeFileSync "#{folder}/rules", ENQUEUE_TEST
    execFuture("#{binplz} -f rules start").then (p) ->
      p.stdout.should.match(/start\ncontinue\n/)

  describe "can deliver settings to a task", ->
    it "from the command line", futureTest withTempFolder (folder) ->
      fs.writeFileSync "#{folder}/rules", SETTINGS_TEST_1
      execFuture("#{binplz} -f rules citrus=\'hello there\'").then (p) ->
        p.stdout.should.match(/^hello there\n/)

    it "from a .plzrc file", futureTest withTempFolder (folder) ->
      fs.writeFileSync "#{folder}/rules", SETTINGS_TEST_1
      fs.writeFileSync "#{folder}/plzrc", "citrus=hello there\n"
      env = { "PLZRC": "#{folder}/plzrc" }
      for k, v of process.env then env[k] = v
      execFuture("#{binplz} -f rules", env: env).then (p) ->
        p.stdout.should.match(/^hello there\n/)

    it "into the run function as a parameter", futureTest withTempFolder (folder) ->
      fs.writeFileSync "#{folder}/rules", SETTINGS_TEST_2
      execFuture("#{binplz} -f rules citrus=\'hello there\'").then (p) ->
        p.stdout.should.match(/^hello there\n/)

  describe "can load modules", ->
    it "from PLZPATH", futureTest withTempFolder (folder) ->
      shell.mkdir "-p", "#{folder}/hidden"
      fs.writeFileSync "#{folder}/hidden/plz-whine.coffee", LOAD_TEST_WHINE
      fs.writeFileSync "#{folder}/rules", LOAD_TEST
      env = { "PLZPATH": "#{folder}/hidden" }
      for k, v of process.env then env[k] = v
      execFuture("#{binplz} -f rules", env: env).then (p) ->
        p.stdout.should.match(/whine.\nloaded.\n/)

    it "from .plz/plugins/", futureTest withTempFolder (folder) ->
      shell.mkdir "-p", "#{folder}/.plz/plugins"
      fs.writeFileSync "#{folder}/.plz/plugins/plz-whine.coffee", LOAD_TEST_WHINE
      fs.writeFileSync "#{folder}/rules", LOAD_TEST
      execFuture("#{binplz} -f rules").then (p) ->
        p.stdout.should.match(/whine.\nloaded.\n/)

    it "delayed from within a file", futureTest withTempFolder (folder) ->
      shell.mkdir "-p", "#{folder}/.plz/plugins"
      fs.writeFileSync "#{folder}/.plz/plugins/plz-whine.coffee", LOAD_TEST_DELAYED
      fs.writeFileSync "#{folder}/rules", LOAD_TEST
      execFuture("#{binplz} -f rules").then (p) ->
        p.stdout.should.match(/whine.\nloaded.\n/)

    it "delayed from within a different file", futureTest withTempFolder (folder) ->
      shell.mkdir "-p", "#{folder}/.plz/plugins"
      fs.writeFileSync "#{folder}/.plz/plugins/plz-smile.coffee", LOAD_TEST_DELAYED_2
      fs.writeFileSync "#{folder}/rules", LOAD_TEST_2
      execFuture("#{binplz} -f rules").then (p) ->
        p.stdout.should.match(/whine.\nloaded.\n/)


SHELL_TEST = """
task "wiggle", run: ->
  touch "aardvark"
  cp "aardvark", "bumblebee"
  mv "aardvark", "cicada"
  warning(ls(".").join(" "))
"""

BEFORE_TEST = """
task "main", run: -> echo "main."
task "barnacle", before: "main", run: -> echo "barnacle."
task "worse", before: "barnacle", run: -> echo "even worse."
"""

AFTER_TEST = """
task "main", run: -> echo "main."
task "barnacle", after: "main", run: -> echo "barnacle."
task "worse", after: "barnacle", run: -> echo "even worse."
"""

AROUND_TEST = """
task "main", description: "plover", run: -> echo "main."
task "barnacle1", before: "main", run: -> echo "barnacle 1."
task "barnacle2", after: "main", run: -> echo "barnacle 2."
"""

EXEC_TEST = """
task "sleeper", run: ->
  exec("sleep 1 && echo hello").then ->
    exec("echo goodbye")
"""

TOPO_TEST = """
task "bee", run: ->
  echo "bee"

task "cat", must: "bee", run: ->
  echo "cat"

task "dog", must: "bee", run: ->
  echo "dog"

task "pets", must: [ "cat", "dog" ], run: ->
  echo "pets!"
"""

RUN_TEST = """
task "main", run: ->
  echo "hello"

task "end", watch: "%FOLDER%/die.x", run: ->
  echo "goodbye"
  process.exit 0

"""

CONFIG_TEST = """
task "test", run: ->
  notice "\#{plz.version()} ok!"
  plz.logVerbose(true)
  info "info 1"
  plz.logVerbose(false)
  info "info 2"
  notice "done"
"""

ENQUEUE_TEST = """
task "start", run: ->
  echo "start"
  runTask "continue"

task "continue", run: ->
  echo "continue"
"""

SETTINGS_TEST_1 = """
task "build", run: ->
  console.log settings.citrus
"""

SETTINGS_TEST_2 = """
task "build", run: (wut) ->
  console.log wut.citrus
"""

LOAD_TEST = """
load "whine"

task "build", run: ->
  console.log "loaded."
"""

LOAD_TEST_WHINE = """
task "prebuild", before: "build", run: ->
  console.log "whine."
"""

LOAD_TEST_DELAYED = """
plugins.whine = ->
  task "prebuild", before: "build", run: ->
    console.log "whine."
"""

LOAD_TEST_DELAYED_2 = """
plugins.whine = ->
  task "prebuild", before: "build", run: ->
    console.log "whine."
"""

LOAD_TEST_2 = """
load "smile"
load "whine"

task "build", run: ->
  console.log "loaded."
"""