const { Before, After, BeforeAll, setWorldConstructor } = require('@cucumber/cucumber')
const { mkdtempSync, rmSync, existsSync } = require('node:fs')
const { tmpdir } = require('node:os')
const { join, resolve } = require('node:path')
const { spawnSync } = require('node:child_process')

const ROOT = resolve(__dirname, '../..')
const BINARY = join(ROOT, '.build', 'debug', 'MyIDECLI')

function runCommand(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: ROOT,
    encoding: 'utf8',
    ...options
  })

  if (result.error) {
    throw result.error
  }

  return result
}

BeforeAll(function () {
  const products = ['MyIDECLI', 'MyIDESampleMacApp']

  for (const product of products) {
    const result = runCommand('swift', ['build', '--product', product])
    if (result.status !== 0) {
      throw new Error(`swift build --product ${product} failed:\n${result.stderr}`)
    }
  }
})

class MyIDEWorld {
  runCli(...args) {
    const result = runCommand(BINARY, args)
    this.lastStdout = result.stdout
    this.lastStderr = result.stderr
    this.lastStatus = result.status

    if (result.status !== 0) {
      throw new Error(`CLI failed: ${result.stderr}`)
    }

    return result.stdout
  }

  runCliJson(...args) {
    return JSON.parse(this.runCli(...args))
  }
}

setWorldConstructor(MyIDEWorld)

Before(function () {
  this.tempDir = mkdtempSync(join(tmpdir(), 'myide-cucumber-'))
  this.workspacePath = join(this.tempDir, 'workspace.json')
  this.currentSession = null
  this.currentWindow = null
  this.currentPane = null
  this.currentSplit = null
  this.currentSplits = null
  this.renderedHtml = null
  this.terminalInteraction = null
  this.dividerResizeResult = null
})

After(function () {
  if (this.tempDir && existsSync(this.tempDir)) {
    rmSync(this.tempDir, { recursive: true, force: true })
  }
})
