---
name: testflight
description: Send a branch to TestFlight with What to Test notes written for testers. Finds the latest TestFlight build, works out what the branch brings over it, writes short readable notes that fold commits doing the same thing into one line and leave out build, CI, docs, spec and test-only changes, then starts the TestFlight workflow with those notes. Use when asked to send, ship or upload a build to TestFlight, or to write TestFlight / What to Test notes.
argument-hint: "[branch] [draft]"
allowed-tools: Bash(gh run list:*), Bash(gh run view:*), Bash(gh workflow view:*), Bash(git log:*), Bash(git show:*), Bash(git diff:*), Bash(git cherry:*), Bash(git rev-parse:*), Bash(git merge-base:*), Bash(git cat-file:*), Bash(git fetch:*), Bash(grep:*), Bash(jj git fetch:*), Bash(jj log:*), Bash(jj diff:*), Bash(jj status:*), Bash(mise exec -- swift scripts/build-number.swift latest)
---

# Send a build to TestFlight

`.github/workflows/testflight.yml` builds the head of a branch **as it is on GitHub**, uploads it,
and puts its `notes` input on the build as What to Test, followed by a line `<short sha> on
<branch>` that the workflow adds itself. Without notes it lists every commit subject since the last
successful run, which is noisy; this skill writes the notes instead and starts the run.

Arguments (`$ARGUMENTS`, both optional, any order):

- a branch (jj bookmark) to send. Without one, use the bookmark on the working copy or its nearest
  ancestor.
- `draft`: write the notes and show them, but do not start the run.

## 1. Find what is being sent

1. Fetch first, so everything below reads what GitHub has: `jj git fetch` (or `git fetch origin` in a
   checkout that is not jj).
2. Pick the branch. Without an argument:
   `jj log -r 'heads(::@ & bookmarks())' --no-graph -T 'local_bookmarks.map(|b| b.name()).join(" ") ++ "\n"'`.
   Several, or none: ask which one.
3. The target is `origin/<branch>`. Look for app changes that are not on GitHub:
   `jj log -r '<branch>@origin..<branch>'` (unpushed commits on the bookmark) and, when the working
   copy sits on that branch,
   `jj diff --stat --from <branch>@origin --to @ -- App Shared WatchApp Widgets Packages Project.swift`.
   Changes outside those paths never reach a tester; mention them in a line at most. If app changes
   are missing from GitHub, say they are **not** in the build, ask whether to push first, and stop
   until the user answers (a `draft` carries on). Never push for the user.
4. The workflow file on the target must have the `notes` input:
   `git show origin/<branch>:.github/workflows/testflight.yml | grep -q '^      notes:'`. If it does
   not, `gh workflow run -f notes=…` is refused, because `--ref` reads the workflow from the branch.
   Say the branch needs a `testflight.yml` with the input (rebase it onto, or merge, a branch that
   has it), and stop, unless this is a `draft`.

## 2. Find the latest TestFlight build

Use both sources and say which build you compare against.

- **The workflow's runs**:
  `gh run list --workflow testflight.yml --limit 20 --json databaseId,status,conclusion,headSha,headBranch,createdAt,url`.
  The newest `success` is the last build sent by CI. Its build number is in its log:
  `gh run view <id> --log | grep -m1 -o 'Build [0-9]* is on App Store Connect'` (logs expire after
  90 days, so this can come back empty).
- **App Store Connect**: `mise exec -- swift scripts/build-number.swift latest` prints the newest
  upload's number, date and processing state, then its What to Test. The last line of those notes
  is `<short sha> on <branch>`: the commit it was built from. This needs the App Store Connect key
  from `mise.local.toml`; if it fails, go by the runs alone and say so.

If App Store Connect has a newer build than the last successful run (one uploaded from a Mac, or a
run that uploaded and then failed), compare against the commit on its last line. If no source ties
the latest build to a commit, show what you found and ask which commit to compare against.

Also look at runs that are `queued` or `in_progress`:

- One **in progress** of another commit will be the latest build if it succeeds, and a new run
  waits behind it. Ask whether to compare against it or against the last build that is up.
- One **queued** is replaced by a new run (the workflow's concurrency group). Say so before starting.

If the target commit is the one the latest build, or a run in progress, was built from, there is
nothing new to send: a run would only upload the same code again. Say so, write the notes against
the build before it, and offer to put them on that build instead of starting a run:
`mise exec -- swift scripts/build-number.swift notes <number> <notes file>`, once that build is
listed and its run has finished (the run's last step sets its own notes and would replace them).

## 3. Work out what changed for a tester

Let `<base>` be the commit of the latest build and `<target>` be `origin/<branch>`. Make sure
`<base>` exists locally (`git cat-file -e <base>^{commit}`).

- `git cherry -v <base> <target>` lists the target's commits; `+` is new, `-` is a copy of one the
  last build already had (jj rewrites commits, so the same change often has a new hash). When
  `<base>` is not an ancestor of `<target>` (`git merge-base --is-ancestor <base> <target>` fails),
  also treat a commit with the same subject as one in `git log <target>..<base>` as already shipped.
- `git cherry -v <target> <base>` lists what the last build had that this one does not. If any of
  that is something testers used, it goes in the notes ("Not in this build: …").
- Read the bodies (`git log --format='%h %s%n%b' <base>..<target>`) and the overall diff of the
  app's code, which shows where commits cancel out or build on each other:
  `git diff --stat <base> <target> -- App Shared WatchApp Widgets Packages ':!**/Tests/**' Project.swift`.
  Open the diff itself where a subject leaves you unsure what a tester would see.

Keep only what someone holding the phone or the watch could notice: new features, changed
behaviour or screens, fixed bugs, crashes, performance, battery, connection reliability, changed
device support.

Leave out, whatever their commit type:

- `build:`, `ci:`, `chore:`, `docs:`, `test:`, `style:` commits, and any commit whose app diff
  changes nothing a tester could notice, whatever its type: a `fix:` that only makes code testable,
  a `refactor:`, code that nothing calls yet, a launch argument only screenshots use.
- `specs/`, `.specify/`, `docs/` (the website), `fastlane/` (the App Store listing), `scripts/`,
  `.github/`, `.claude/`, README and other Markdown, and anything under `Tests/`.
- Changes to `Project.swift`, `Tuist.swift` or `mise.toml`, unless they change what is installed:
  the minimum OS, a permission prompt, the app's name or icon, a new extension.
- Fixes to something that is new in this build. A `feat:` and the `fix:` commits that follow it
  are one New line, not a New line plus Fixed lines.
- Internal names: wire, record, transport, stand-in, store, harness. Say what the tester sees.

## 4. Write the notes

- English, plain words, written to the tester: what changed and what to try. Not commit subjects
  reworded; one line can cover many commits.
- Sections, each only when it has something, in this order: `New`, `Changed`, `Fixed`,
  `Not in this build`. Each line starts with `• `. A line `Please try: …` above them is worth it
  when one thing needs testing most, such as a setup with several devices.
- Never promise more than the code does: check limits, counts and wording against the source.
- Short: a tester reads it on a phone. Aim for under 1,000 characters; App Store Connect cuts
  What to Test at 4,000.
- No commit hashes, branch names, ticket numbers or Markdown. The workflow adds the commit line.
- If nothing a tester would notice changed, write one line that says so, for example
  `Under-the-hood changes only; nothing new to test.`, and ask whether to send the build anyway.

## 5. Start the run

Show the notes, the branch, the commit and the build it is compared against. With `draft`, stop
here.

Otherwise write the notes to a file in your scratchpad and start the run:

```bash
gh workflow run testflight.yml --ref <branch> -f notes="$(cat <notes file>)"
```

Then `gh run list --workflow testflight.yml --limit 1 --json databaseId,url,status` (give it a few
seconds to appear) and give the user the run's link. Do not watch the run; it takes 30–60 minutes.
