Feature: Terminal and diff panes
  Scenario: Run a shell command inside a terminal pane
    Given a fresh workspace
    When I create a session named "Shell Work"
    And I create a window named "Console" in the current session
    And I add a terminal pane titled "Main Shell" using provider "ghostty" to the current window
    And I run "printf 'hello from myide'" in the current pane
    Then the current pane exit code should be 0
    And the current pane output should include "hello from myide"

  Scenario: Refresh a diff pane against two files
    Given a fresh workspace
    And a text file "before.txt" with content:
      """
      line one
      line two
      """
    And a text file "after.txt" with content:
      """
      line one
      line three
      """
    When I create a session named "Review"
    And I create a window named "Diff" in the current session
    And I add a diff pane titled "Patch" comparing "before.txt" and "after.txt" to the current window
    And I refresh the current pane diff
    Then the current pane output should include "-line two"
    And the current pane output should include "+line three"
