---
name: agent-rules
description: Load applicable repository rules and linked contracts before reviewing or changing code, and when entering another repository or subsystem.
---

# Agent Rules

Load the repository instructions needed for a review or change. This skill does not install,
rewrite, or enforce rules; setup owns installation.

1. Resolve each target repository, including siblings reached during the task. Read its root
   `AGENTS.override.md` or `AGENTS.md` and applicable nested instruction files. Reuse full text
   already loaded in this session; a filename, heading list, or summary is not the rule body.
2. Follow the repository's rule index when present. Also inspect the inventory and frontmatter of
   `.claude/rules/**/*.md` so an outdated index cannot hide a newly added rule. Read every rule
   without `paths`, then the full bodies of rules whose scope covers the files or behaviour being
   reviewed or changed, including planned new files. Resolve patterns relative to their owning
   project, not the plugin or shell directory.
3. Read relevant architecture, contracts, and procedures linked by those rules. If scope is
   ambiguous, read the rule before deciding whether it applies. Report missing required files or
   conflicting instructions.
4. Revisit selection when the task crosses a subsystem or repository boundary. Briefly name the
   rule files read and any unresolved gap, then continue the user's task.

Skip bodies Claude Code already loaded natively. Codex does not inject sibling instruction files
when you open a source file, so read them explicitly.
