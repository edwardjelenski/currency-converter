# Currency Converter — instructions for the agent

Course project: iOS client (`src/ios`, XcodeGen) + Swift REST server with SQLite (`src/server`,
`Package.swift` in the repo root) + Docker Compose. The app talks only to our server, never to
external APIs directly. Docs and agent artifacts are in Russian.

## Agent artifacts in `.agent/` — keep them current on every turn

These are graded course artifacts. Update them in the same turn as the work, and commit them with it.

- **`.agent/prompt-log.md`** — after every user message, append an entry: the request **verbatim**
  (in a ```text block, including any pasted text), date and time (`date '+%Y-%m-%d %H:%M'`),
  a short "what was done", files touched, and commits (hash + subject; for this turn's own
  commit, the subject is enough). Questions with no code changes are logged too.
- **`.agent/errors.md`** — whenever something goes wrong on the agent's side (build fails,
  test fails, a command errors or does nothing useful, the task was misunderstood, the user
  had to correct the agent): add an entry with *Когда / Что было / Причина / Как исправил*.
  Log it honestly even if it was fixed right away.
- **`.agent/config.json`** — model, permission mode, and the tools, MCP servers and CLI
  commands *actually used*. Add anything new used this turn; never list unused tools.

Key prompts get a fuller write-up in `PROMPTS.md`; lessons go to `REFLECTION.md`.

## Workflow

- Commit straight to `main` with meaningful messages and `git push` after each step.
- iOS: run `xcodegen generate` in `src/ios` after adding/removing files; the `.xcodeproj` is not committed.
- Run tests with `-enableCodeCoverage NO -parallel-testing-enabled NO` (otherwise `xcodebuild test`
  may hang after the run, see `.agent/errors.md` #3). Reuse an existing simulator.
- The user's shell is zsh: no `PIPESTATUS`, and unmatched globs in arguments fail.
