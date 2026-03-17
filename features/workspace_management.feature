Feature: Workspace management
  Scenario: Sessions map to app windows while windows map to LNB entries
    When I headless-check session and window semantics
    Then the first session should map to 1 app window
    And the first session should start with 0 LNB windows
    And adding a window should make the first session show 1 LNB windows
    And the first session LNB should include window title "Editor"
    And the second session should map to 2 app windows
    And the second session should start with 0 LNB windows

  Scenario: Switching from an empty window back to Main keeps all Main panes
    When I headless-check switching from an empty window back to Main
    Then the Main window should keep 3 panes after returning
    And switching back to Main should not raise an error

  Scenario: Build a practical workspace with multiple pane types
    Given a fresh workspace
    When I create a session named "Client Delivery"
    And I create a window named "Editor" in the current session
    And I add a browser pane titled "Docs" with URL "https://swift.org" to the current window
    And I add a markdown preview pane titled "Spec" for file "spec.md" to the current window
    Then the workspace should have 1 session
    And the current window should have 2 panes
    And the current window should include a "browser" pane titled "Docs"
    And the current window should include a "markdownPreview" pane titled "Spec"
