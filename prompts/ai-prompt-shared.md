I'd like you to merge, refine, dedup and logistically order the step-by-step parts of the list to make it easy for me to go through everything while I'm completing all the tasks on the checklists you're generating.

Please check all existing tasks you know are already completed and mark them as finished in the list. Please also add any subtasks you think are necessary to complete the main tasks.

Format rules:
- Output the list as clean plain text only - no conversational preamble.
- This is NOT standard YAML, so do NOT try to "fix" it into strict YAML and do NOT add task: / checked: / subtasks: keys. Follow the shape below exactly.
- Use strictly 2-space indentation for subtasks. Never use tabs.
- Write tasks with the three-state marker: "- [ ] untouched", "- [v] Yes (approved/done)", "- [x] No (rejected/ignored)". Never use [x] to mean done.
- Nest subtasks exactly 2 additional spaces deeper than their parent task, one step per nesting level.
- Each milestone uses metadata keys:

```
section: "Goal/Milestone Name"
description: "Overview, objectives and prerequisites..."
tasks:
```

- Notes sit under their task on a `notes: "..."` line, or as a multi-line block:

```
notes: |
  line one
  line two
```

  The notes: key sits 2 spaces deeper than its task's "- ", and a multi-line body sits 2 spaces deeper again (never aligned with the "- ").

- Comments are NOT yours to invent. If the list you are given already carries a "comments: |" block on a task or a section, reproduce it EXACTLY as it was (same lines, same order). When you are explicitly asked to add a comment, write it as a "comments: |" block one indent step under the node, one comment per line, as "Name: text" - the author's name, a colon, a space, then the text in one line. Example:

```
  - [ ] Task Title
    notes: "Helpful instructions or links"
    comments: |
      Day: I tried this and it tasted awful
      Brian: The benefits are still worth it
```

- Use clean section names WITHOUT numbers (e.g. section: "Cloudflare Infrastructure") because List Puncher automatically numbers milestones dynamically.
- Include a full, detailed description under each section explaining the objectives, prerequisites, and context (descriptions can be as long as needed).
- Feel free to include YouTube video/tutorial links (including timestamps such as ?t=111s) and image links inside task notes or descriptions (List Puncher auto-renders them into video players and images).
- Nesting depth limit doesn't exist. Nest the tasks as deep as needed.

List Structure:

```
section: "Goal/Milestone Name"
description: |
  Multi-line overview of this goal/milestone...
tasks:
  - [ ] Task Title
    notes: "Helpful instructions or links"
    - [ ] Subtask Title
      notes: |
        Diagram Example:
        https://www.example.com/diagram.png
```
