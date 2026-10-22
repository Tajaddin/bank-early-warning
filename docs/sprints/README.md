# How this project is run

Scrum, scaled to one developer:

- **Backlog** as data (`docs/agile/backlog.json`), synced to GitHub issues with labels for type, area and story
  points (`scripts/agile/sync_backlog.py`). Every story has acceptance criteria.
- **Sprints** are GitHub milestones with a goal. Work happens on a `sprint-N` branch; commits reference their
  issue (`(#3)`); the sprint ends with one pull request whose description closes the sprint's issues, merged only
  when CI is green.
- **Definition of done**: tests for the behaviour, CI green, every number in the docs traced to a committed report
  file, secret scan clean.
- **Evaluation discipline**: the model is fitted on 2007-2009 report dates and evaluated once on 2011-2012
  (ADR 0001).
- **Retro** at the end of each sprint, committed here: the goal, what shipped, what was measured, what went well,
  what did not, and what carries over.
- Work found during a sprint (a bug, a missing piece) becomes an issue in that sprint or the next one, not a silent
  change. Work that needs an account stays in the **Backlog** milestone, labelled `blocked:account`.
- The board: [GitHub Projects](https://github.com/users/Tajaddin/projects/6), one card per issue, with Sprint and
  Status fields kept in step with the milestones.
