Feature: Terminal input focus
  Scenario: Terminal pane runs commands inside a real embedded terminal
    When I UI-run terminal command "pwd" expecting output "/Users/leejs/Project/myide"
    Then terminal surface should receive typing "pwd"
    And terminal snapshot should include "/Users/leejs/Project/myide"
