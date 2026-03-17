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
