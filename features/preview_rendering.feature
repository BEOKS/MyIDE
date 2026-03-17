Feature: Preview panes
  Scenario: Render markdown with Mermaid support
    Given a fresh workspace
    And a markdown file "diagram.md" with content:
      """
      # Architecture

      ```mermaid
      flowchart LR
        Session --> Window
        Window --> Pane
      ```
      """
    When I create a session named "Docs"
    And I create a window named "Preview" in the current session
    And I add a markdown preview pane titled "Architecture" for file "diagram.md" to the current window
    And I render markdown file "diagram.md"
    Then the current window should include a "markdownPreview" pane titled "Architecture"
    And the rendered html should include "marked.min.js"
    And the rendered html should include "language-mermaid"

  Scenario: Store an image preview pane for a local asset
    Given a fresh workspace
    And an image file "pixel.png"
    When I create a session named "Assets"
    And I create a window named "Preview" in the current session
    And I add an image preview pane titled "Pixel" for file "pixel.png" to the current window
    Then the current window should include a "imagePreview" pane titled "Pixel"

  Scenario: Select a markdown file through the preview file picker
    Given a markdown file "selected.md" with content:
      """
      # Selected
      """
    When I headless-select preview file "selected.md" through the file picker
    Then selected file path should equal "selected.md"

  Scenario: Select a diff file through the diff file picker
    Given a text file "left.txt" with content:
      """
      left side
      """
    When I headless-select diff file "left.txt" through the file picker
    Then selected file path should equal "left.txt"
