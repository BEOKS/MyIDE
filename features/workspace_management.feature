Feature: Workspace management
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
