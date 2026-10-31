# Contributing to FuseFire

FuseFire is an owner-led indie game. Melo9002 owns the project's direction and makes the final decisions about gameplay, narrative, visual style, architecture and what ships. Contributions and experiments are welcome within an agreed scope.

## Agree on the task

Before starting substantial work, agree with the owner on the goal and the systems or assets involved. Suggestions are welcome; changes to the game's direction or expansion into other systems need discussion before implementation. Expertise helps inform decisions without transferring creative control.

For animation work, experiment with animation assets and their agreed integration. Discuss changes to character design, combat timing, movement rules, shared rigs or asset import settings before expanding the task.

## Work on a branch

- Use your existing collaboration branch or a focused branch such as `animation/walk-cycle`.
- Keep changes focused and preserve unrelated work. Do not delete, replace or reorganize assets or systems outside the agreed task.
- Open a pull request to `main` when you want the work integrated. Draft pull requests are welcome for early feedback.
- Explain what changed, how to try it, what you tested, and any remaining issues. Animation changes should include a short capture where practical.
- Wait for Melo9002's approval before merging. New changes after approval require another review. Approval to experiment does not automatically mean approval to ship.

## Project checks

Follow `AGENTS.md` and `docs/quality/project-ironclad.md`. Run checks relevant to your change and report failures honestly. For visual changes, inspect the result in Godot; passing headless tests does not establish visual quality. Preserve useful regression coverage.

## Owner workflow and review authority

The owner can commit and push directly to `main` through the repository-admin bypass. Collaborators do not receive that bypass. Changes targeting `main` require a pull request and code-owner approval from Melo9002. `.github/CODEOWNERS` covers every file, including the review policy itself.

The owner may request revisions, postpone a contribution or decline it when it does not fit the game. We discuss the work respectfully and keep the scope clear so contributors do not spend time on a direction the project will not pursue.
