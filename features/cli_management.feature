Feature: CLI management
  Scenario: Manage sessions, windows, and panes through the CLI
    Given a fresh workspace
    When I create a session named "Ops"
    And I show the current session
    Then the shown session name should be "Ops"
    When I rename the current session to "Operations"
    And I show the current session
    Then the shown session name should be "Operations"
    When I create a window named "Dashboard" in the current session
    And I show the current window
    Then the shown window title should be "Dashboard"
    When I rename the current window to "Control"
    And I show the current window
    Then the shown window title should be "Control"
    When I add a browser pane titled "Docs" with URL "https://swift.org" to the current window
    And I show the current pane
    Then the shown pane title should be "Docs"
    And the shown pane kind should be "browser"
    When I update the current browser pane URL to "https://developer.apple.com"
    And I rename the current pane to "Reference"
    And I show the current pane
    Then the shown pane title should be "Reference"
    And the shown browser URL should be "https://developer.apple.com"
    When I delete the current pane
    Then the current window should have 0 panes
    When I delete the current window
    Then the shown session should have 0 windows
    When I delete the current session
    Then the workspace should have 0 sessions
