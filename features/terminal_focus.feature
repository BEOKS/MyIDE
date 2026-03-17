Feature: Terminal input focus
  Scenario: Clicking the embedded terminal sends typing into the pane
    When I headless-check terminal click-to-type with text "echo focused"
    Then terminal editor should be focused
    And terminal surface should receive typing "echo focused"

  Scenario: Terminal pane fills the pane like a terminal app
    When I headless-check terminal pane layout
    Then terminal pane width ratio should be greater than 0.78
    And terminal pane height ratio should be greater than 0.6

  Scenario: Pane chrome hides the title and close button
    When I headless-check pane chrome
    Then pane count should be 1
    And pane title should not be visible
    And pane close button should not be visible

  Scenario: Terminal pane runs commands inside a real embedded terminal
    When I headless-run terminal command "pwd" expecting output "$ROOT"
    Then terminal editor should be focused
    And terminal surface should receive typing "pwd"
    And terminal snapshot should include "$ROOT"

  Scenario: Terminal emulator applies ANSI cursor movement instead of logging raw output
    When I headless-run the ANSI cursor movement sample
    Then terminal snapshot should include "1X3"

  Scenario: Ctrl+D closes the terminal pane
    When I headless-send ctrl+d to the terminal pane
    Then terminal pane should close
    And pane count should be 0
