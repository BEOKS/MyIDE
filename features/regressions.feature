Feature: Regression prevention
  Scenario: Reselecting Main after visiting an empty window preserves all Main panes
    When I headless-check the Main window reselection regression
    Then the Main window should keep 3 panes after returning
    And the scratch window should keep 0 panes
    And the Main window should preserve pane titles:
      | Shell 1 |
      | Docs    |
      | Shell 2 |
    And switching back to Main should not raise an error

  Scenario: Add pane sheet is scoped to the session window that opened it
    When I headless-check add pane sheet scoping across session windows
    Then the first session window should show the add pane sheet
    And the second session window should not show the add pane sheet

  Scenario: New sessions start with a Main window so add pane is enabled
    When I headless-check new session defaults
    Then the new session should start with 1 windows in LNB
    And the new session first window title should be "Main"
    And the add pane button should be enabled for the new session

  Scenario: Terminal IME composition keeps marked text until final commit
    When I headless-check terminal IME composition handling
    Then the terminal should keep marked text during composition
    And the terminal should commit the final IME text "한"
    And the terminal should clear marked text after commit

  Scenario: Cmd+Backspace deletes to the beginning of the terminal line
    When I headless-check cmd+backspace terminal shortcut handling
    Then the terminal should delete to the beginning of the line

  Scenario: Tmux split shortcuts build directional pane layouts
    When I headless-check tmux split shortcuts
    Then the tmux split shortcuts should produce 3 panes
    And the vertical split shortcut should create a "vertical" root split
    And the final tmux split layout should include "horizontal"
