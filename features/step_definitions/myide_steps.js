const assert = require('node:assert/strict')
const { Given, When, Then } = require('@cucumber/cucumber')
const { writeFileSync } = require('node:fs')
const { join } = require('node:path')

function resolveToken(value) {
  if (value === '$ROOT') {
    return process.cwd()
  }

  return value
}

function resolveFixturePath(world, value) {
  return join(world.tempDir, value)
}

function normalizeTerminalCommand(command) {
  return command
    .replace(/\u001b/g, '\\033')
    .replace(/\r/g, '\\r')
    .replace(/\n/g, '\\n')
}

Given('a fresh workspace', function () {
  this.runCli('init', '--workspace', this.workspacePath)
})

Given('a text file {string} with content:', function (name, content) {
  writeFileSync(join(this.tempDir, name), content)
})

Given('a markdown file {string} with content:', function (name, content) {
  writeFileSync(join(this.tempDir, name), content)
})

Given('an image file {string}', function (name) {
  const pngData = [
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4',
    '//8/AwAI/AL+X8X+9QAAAABJRU5ErkJggg=='
  ].join('')

  writeFileSync(join(this.tempDir, name), Buffer.from(pngData, 'base64'))
})

When('I create a session named {string}', function (name) {
  this.currentSession = this.runCliJson(
    'add-session',
    '--workspace', this.workspacePath,
    '--name', name
  )
})

When('I create a window named {string} in the current session', function (title) {
  this.currentWindow = this.runCliJson(
    'add-window',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--title', title
  )
})

When('I add a terminal pane titled {string} using provider {string} to the current window', function (title, provider) {
  this.currentPane = this.runCliJson(
    'add-pane',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--window-id', this.currentWindow.id,
    '--kind', 'terminal',
    '--title', title,
    '--provider', provider
  )
})

When('I add a browser pane titled {string} with URL {string} to the current window', function (title, url) {
  this.currentPane = this.runCliJson(
    'add-pane',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--window-id', this.currentWindow.id,
    '--kind', 'browser',
    '--title', title,
    '--url', url
  )
})

When('I add a diff pane titled {string} comparing {string} and {string} to the current window', function (title, leftName, rightName) {
  this.currentPane = this.runCliJson(
    'add-pane',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--window-id', this.currentWindow.id,
    '--kind', 'diff',
    '--title', title,
    '--left', join(this.tempDir, leftName),
    '--right', join(this.tempDir, rightName)
  )
})

When('I add a markdown preview pane titled {string} for file {string} to the current window', function (title, fileName) {
  this.currentPane = this.runCliJson(
    'add-pane',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--window-id', this.currentWindow.id,
    '--kind', 'markdown',
    '--title', title,
    '--file', join(this.tempDir, fileName)
  )
})

When('I add an image preview pane titled {string} for file {string} to the current window', function (title, fileName) {
  this.currentPane = this.runCliJson(
    'add-pane',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--window-id', this.currentWindow.id,
    '--kind', 'image',
    '--title', title,
    '--file', join(this.tempDir, fileName)
  )
})

When('I run {string} in the current pane', function (command) {
  this.currentPane = this.runCliJson(
    'run-terminal',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--window-id', this.currentWindow.id,
    '--pane-id', this.currentPane.id,
    '--command', command
  )
})

When('I refresh the current pane diff', function () {
  this.currentPane = this.runCliJson(
    'refresh-diff',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--window-id', this.currentWindow.id,
    '--pane-id', this.currentPane.id
  )
})

When('I render markdown file {string}', function (fileName) {
  this.renderedHtml = this.runCli(
    'render-markdown',
    '--file', join(this.tempDir, fileName)
  )
})

When('I show the current session', function () {
  this.currentSession = this.runCliJson(
    'show-session',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id
  )
})

When('I rename the current session to {string}', function (name) {
  this.currentSession = this.runCliJson(
    'update-session',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--name', name
  )
})

When('I delete the current session', function () {
  this.workspaceSnapshot = this.runCliJson(
    'delete-session',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id
  )
  this.currentSession = null
})

When('I show the current window', function () {
  this.currentWindow = this.runCliJson(
    'show-window',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--window-id', this.currentWindow.id
  )
})

When('I rename the current window to {string}', function (title) {
  this.currentWindow = this.runCliJson(
    'update-window',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--window-id', this.currentWindow.id,
    '--title', title
  )
})

When('I delete the current window', function () {
  this.currentSession = this.runCliJson(
    'delete-window',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--window-id', this.currentWindow.id
  )
  this.currentWindow = null
})

When('I show the current pane', function () {
  this.currentPane = this.runCliJson(
    'show-pane',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--window-id', this.currentWindow.id,
    '--pane-id', this.currentPane.id
  )
})

When('I rename the current pane to {string}', function (title) {
  this.currentPane = this.runCliJson(
    'update-pane',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--window-id', this.currentWindow.id,
    '--pane-id', this.currentPane.id,
    '--title', title
  )
})

When('I update the current browser pane URL to {string}', function (url) {
  this.currentPane = this.runCliJson(
    'update-pane',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--window-id', this.currentWindow.id,
    '--pane-id', this.currentPane.id,
    '--url', url
  )
})

When('I delete the current pane', function () {
  this.currentWindow = this.runCliJson(
    'delete-pane',
    '--workspace', this.workspacePath,
    '--session-id', this.currentSession.id,
    '--window-id', this.currentWindow.id,
    '--pane-id', this.currentPane.id
  )
  this.currentPane = null
})

When('I check terminal click-to-type with text {string}', function (text) {
  this.terminalInteraction = this.runCliJson(
    'check-terminal-input',
    '--typed-text', text
  )
})

When('I headless-check terminal click-to-type with text {string}', function (text) {
  this.terminalInteraction = this.runCliJson(
    'headless-check-terminal-input',
    '--typed-text', text
  )
})

When('I headless-check terminal pane layout', function () {
  this.terminalLayout = this.runCliJson('headless-check-terminal-layout')
})

When('I headless-check pane chrome', function () {
  this.terminalInteraction = this.runCliJson('headless-check-pane-chrome')
})

When('I headless-run terminal command {string} expecting output {string}', function (command, expectedOutput) {
  this.terminalInteraction = this.runCliJson(
    'headless-run-terminal-command',
    '--command', normalizeTerminalCommand(command),
    '--expected-output', resolveToken(expectedOutput)
  )
})

When('I headless-run the ANSI cursor movement sample', function () {
  this.terminalInteraction = this.runCliJson(
    'headless-run-terminal-command',
    '--command', "printf '123'; printf '\\033[2D'; printf 'X\\n'",
    '--expected-output', '1X3'
  )
})

When('I headless-send ctrl+d to the terminal pane', function () {
  this.terminalInteraction = this.runCliJson('headless-send-terminal-eot')
})

When('I headless-select preview file {string} through the file picker', function (fileName) {
  this.terminalInteraction = this.runCliJson(
    'headless-select-preview-file',
    '--selected-file', resolveFixturePath(this, fileName)
  )
})

When('I headless-select diff file {string} through the file picker', function (fileName) {
  this.terminalInteraction = this.runCliJson(
    'headless-select-diff-file',
    '--selected-file', resolveFixturePath(this, fileName)
  )
})

When('I headless-check session and window semantics', function () {
  this.windowSemantics = this.runCliJson('headless-check-session-window-semantics')
})

When('I headless-check switching from an empty window back to Main', function () {
  this.windowSemantics = this.runCliJson('headless-check-empty-window-switch')
})

When('I headless-check the Main window reselection regression', function () {
  this.windowSemantics = this.runCliJson('headless-check-main-window-reselection-regression')
})

When('I headless-check add pane sheet scoping across session windows', function () {
  this.windowSemantics = this.runCliJson('headless-check-add-pane-sheet-scope')
})

When('I headless-check new session defaults', function () {
  this.windowSemantics = this.runCliJson('headless-check-new-session-defaults')
})

When('I headless-check terminal IME composition handling', function () {
  this.terminalInteraction = this.runCliJson('headless-check-ime-composition')
})

When('I headless-check cmd+backspace terminal shortcut handling', function () {
  this.terminalInteraction = this.runCliJson('headless-check-delete-line-shortcut')
})

When('I headless-check tmux split shortcuts', function () {
  this.windowSemantics = this.runCliJson('headless-check-tmux-split-shortcuts')
})

Then('the workspace should have {int} session', function (count) {
  const workspace = this.runCliJson('show', '--workspace', this.workspacePath)
  assert.equal(workspace.sessions.length, count)
})

Then('the workspace should have {int} sessions', function (count) {
  const workspace = this.runCliJson('show', '--workspace', this.workspacePath)
  assert.equal(workspace.sessions.length, count)
})

Then('the shown session name should be {string}', function (name) {
  assert.equal(this.currentSession.name, name)
})

Then('the shown session should have {int} windows', function (count) {
  assert.equal(this.currentSession.windows.length, count)
})

Then('the current window should have {int} panes', function (count) {
  const workspace = this.runCliJson('show', '--workspace', this.workspacePath)
  const session = workspace.sessions.find((item) => item.id === this.currentSession.id)
  const window = session.windows.find((item) => item.id === this.currentWindow.id)
  assert.equal(window.panes.length, count)
})

Then('the shown window title should be {string}', function (title) {
  assert.equal(this.currentWindow.title, title)
})

Then('the current window should include a {string} pane titled {string}', function (kind, title) {
  const workspace = this.runCliJson('show', '--workspace', this.workspacePath)
  const session = workspace.sessions.find((item) => item.id === this.currentSession.id)
  const window = session.windows.find((item) => item.id === this.currentWindow.id)
  const pane = window.panes.find((item) => item.kind === kind && item.title === title)
  assert.ok(pane)
})

Then('the shown pane title should be {string}', function (title) {
  assert.equal(this.currentPane.title, title)
})

Then('the shown pane kind should be {string}', function (kind) {
  assert.equal(this.currentPane.kind, kind)
})

Then('the shown browser URL should be {string}', function (url) {
  assert.equal(this.currentPane.browser.urlString, url)
})

Then('the current pane exit code should be {int}', function (exitCode) {
  assert.equal(this.currentPane.terminal.lastExitCode, exitCode)
})

Then('the current pane output should include {string}', function (text) {
  let body = this.lastStdout || ''

  if (this.currentPane?.terminal) {
    body = this.currentPane.terminal.lastOutput
  } else if (this.currentPane?.diff) {
    body = this.currentPane.diff.lastDiff
  }

  assert.ok(body.includes(text), `Expected output to include "${text}" but got:\n${body}`)
})

Then('the rendered html should include {string}', function (text) {
  assert.ok(this.renderedHtml.includes(text))
})

Then('terminal click focus should be true', function () {
  assert.equal(this.terminalInteraction.focusedAfterClick, true)
})

Then('terminal typed text should equal {string}', function (text) {
  const actual = this.terminalInteraction.typedText ?? this.terminalInteraction.editorValue
  assert.equal(actual, text)
})

Then('terminal transcript should include {string}', function (text) {
  const transcript = this.terminalInteraction.editorValue ?? this.terminalInteraction.typedText ?? ''
  assert.ok(transcript.includes(text), `Expected transcript to include "${text}" but got:\n${transcript}`)
})

Then('terminal snapshot should include {string}', function (text) {
  text = resolveToken(text)
  const snapshot = this.terminalInteraction.editorValue ?? this.terminalInteraction.typedText ?? ''
  assert.ok(snapshot.includes(text), `Expected terminal snapshot to include "${text}" but got:\n${snapshot}`)
})

Then('terminal surface should receive typing {string}', function (text) {
  text = resolveToken(text)
  const snapshot = this.terminalInteraction.editorValue ?? ''
  assert.ok(snapshot.includes(text), `Expected terminal surface to receive typing "${text}" but got:\n${snapshot}`)
})

Then('terminal app should become frontmost', function () {
  assert.equal(this.terminalInteraction.frontmostApplication, 'MyIDESampleMacApp')
})

Then('terminal editor should be focused', function () {
  assert.equal(this.terminalInteraction.editorFocused, true)
})

Then('terminal pane width ratio should be greater than {float}', function (value) {
  assert.ok(this.terminalLayout.widthRatio > value, `Expected width ratio > ${value} but got ${this.terminalLayout.widthRatio}`)
})

Then('terminal pane height ratio should be greater than {float}', function (value) {
  assert.ok(this.terminalLayout.heightRatio > value, `Expected height ratio > ${value} but got ${this.terminalLayout.heightRatio}`)
})

Then('pane count should be {int}', function (count) {
  assert.equal(this.terminalInteraction.paneCount, count)
})

Then('pane title should not be visible', function () {
  assert.equal(this.terminalInteraction.titleVisible, false)
})

Then('pane close button should not be visible', function () {
  assert.equal(this.terminalInteraction.closeButtonVisible, false)
})

Then('terminal pane should close', function () {
  assert.equal(this.terminalInteraction.paneClosed, true)
})

Then('selected file path should equal {string}', function (fileName) {
  assert.equal(this.terminalInteraction.selectedPath, resolveFixturePath(this, fileName))
})

Then('the first session should map to {int} app window', function (count) {
  assert.equal(this.windowSemantics.appWindowCountAfterFirstSession, count)
})

Then('the first session should start with {int} LNB windows', function (count) {
  assert.equal(this.windowSemantics.sidebarWindowCountAfterFirstSession, count)
})

Then('adding a window should make the first session show {int} LNB windows', function (count) {
  assert.equal(this.windowSemantics.sidebarWindowCountAfterAddingWindow, count)
})

Then('the first session LNB should include window title {string}', function (title) {
  assert.ok(this.windowSemantics.sidebarWindowTitlesForFirstSession.includes(title))
})

Then('the second session should map to {int} app windows', function (count) {
  assert.equal(this.windowSemantics.appWindowCountAfterSecondSession, count)
})

Then('the second session should start with {int} LNB windows', function (count) {
  assert.equal(this.windowSemantics.sidebarWindowCountForSecondSession, count)
})

Then('the Main window should keep {int} panes after returning', function (count) {
  assert.equal(this.windowSemantics.mainPaneCountAfterReturn, count)
})

Then('switching back to Main should not raise an error', function () {
  assert.equal(this.windowSemantics.canReturnToMainWithoutError, true)
})

Then('the scratch window should keep {int} panes', function (count) {
  assert.equal(this.windowSemantics.scratchPaneCount, count)
})

Then('the Main window should preserve pane titles:', function (table) {
  const expected = table.raw().flat()
  assert.deepEqual(this.windowSemantics.mainPaneTitlesAfterReturn, expected)
})

Then('the first session window should show the add pane sheet', function () {
  assert.equal(this.windowSemantics.firstWindowShowingSheet, true)
})

Then('the second session window should not show the add pane sheet', function () {
  assert.equal(this.windowSemantics.secondWindowShowingSheet, false)
})

Then('the new session should start with {int} windows in LNB', function (count) {
  assert.equal(this.windowSemantics.windowCount, count)
})

Then('the new session first window title should be {string}', function (title) {
  assert.equal(this.windowSemantics.firstWindowTitle, title)
})

Then('the add pane button should be enabled for the new session', function () {
  assert.equal(this.windowSemantics.addPaneEnabled, true)
})

Then('the terminal should keep marked text during composition', function () {
  assert.equal(this.terminalInteraction.hadMarkedTextDuringComposition, true)
  assert.ok(this.terminalInteraction.firstMarkedRangeLength > 0)
  assert.ok(this.terminalInteraction.updatedMarkedRangeLength > 0)
})

Then('the terminal should commit the final IME text {string}', function (text) {
  assert.equal(this.terminalInteraction.committedText, text)
})

Then('the terminal should clear marked text after commit', function () {
  assert.equal(this.terminalInteraction.hasMarkedTextAfterCommit, false)
})

Then('the terminal should delete to the beginning of the line', function () {
  assert.equal(this.terminalInteraction.succeeded, true)
  assert.ok(this.terminalInteraction.transcript.includes('ok'))
})

Then('the tmux split shortcuts should produce {int} panes', function (count) {
  assert.equal(this.windowSemantics.paneCount, count)
})

Then('the vertical split shortcut should create a {string} root split', function (axis) {
  assert.equal(this.windowSemantics.rootAxisAfterVerticalSplit, axis)
})

Then('the final tmux split layout should include {string}', function (text) {
  assert.ok(this.windowSemantics.finalLayoutDescription.includes(text))
})
