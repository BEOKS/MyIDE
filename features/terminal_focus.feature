Feature: Terminal input focus
  Scenario: Clicking the embedded terminal sends typing into the pane
    When I UI-check terminal click-to-type with text "echo focused"
    Then terminal app should become frontmost
    And terminal surface should receive typing "echo focused"

  Scenario: Terminal pane fills the pane like a terminal app
    When I UI-check terminal pane layout
    Then terminal pane width ratio should be greater than 0.78
    And terminal pane height ratio should be greater than 0.6

  Scenario: Terminal pane runs commands inside a real embedded terminal
    When I UI-run terminal command "pwd" expecting output "/Users/leejs/Project/myide"
    Then terminal app should become frontmost
    And terminal surface should receive typing "pwd"
    And terminal snapshot should include "/Users/leejs/Project/myide"

  Scenario: Terminal emulator applies ANSI cursor movement instead of logging raw output
    When I UI-run terminal command "printf '123'; printf '\\033[2D'; printf 'X\\n'" expecting output "1X3"
    Then terminal snapshot should include "1X3"
