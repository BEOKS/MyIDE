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

  Scenario: Pane split produces equal ratio and removal restores single leaf
    When I headless-check pane split and remove
    Then the split should produce 2 panes
    And the split ratio should be 0.5
    And removing a pane should leave 1 pane
    And the layout after removal should be a single leaf

  Scenario: Nested pane splits preserve layout tree structure
    When I headless-check nested pane split
    Then the nested split should produce 3 panes
    And the nested split root axis should be "horizontal"
    And the nested split child axis should be "vertical"
    And the nested split layout should include "horizontal" and "vertical"
    And the nested split root ratio should be 0.5
    And the nested split child ratio should be 0.5

  Scenario: CLI workspace mutations notify the app and reload correctly
    When I headless-check CLI workspace sync
    Then the initial workspace should have 1 session
    And the workspace change notification should be received
    And the reloaded workspace should have 2 sessions named "Session 1" and "Session 2"
    And after CLI deletes a session only "Session 2" should remain
    And after CLI adds a pane the window should have 1 pane titled "CLI Pane"

  Scenario: Deep nested splits maintain 0.5 ratios and deletions collapse correctly
    When I headless-check pane layout stability
    Then all split ratios should be 0.5 with 4 panes
    And the 4-pane layout should contain 3 levels of nesting
    And deleting a secondary pane should leave 3 panes with all ratios 0.5
    And deleting a primary pane should preserve the sibling in its place
    And deleting down to one pane should produce a single leaf

  Scenario: Ctrl+Shift key events produce correct characters for split shortcuts
    When I headless-check tmux split key matching
    Then the vertical split key should match "%"
    And the horizontal split key should match the quote character
    And the key-matched splits should produce 3 panes
