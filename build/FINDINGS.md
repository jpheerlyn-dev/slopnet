# SlopNet Classroom Walkthrough Findings (T08)

## Chronological Journal of Events & Confusions

1. **Step 1: Simulating "Use this template"**
   - **Action**: Copied the repository contents (excluding `.git` and `build/`) into a new local folder `scratch-classroom`. Initialized git with `git init`, added all files, and made the first commit.
   - **Result**: Worked flawlessly. Git successfully committed all initial template files.
   - **Moment of Confusion**: None. The instructions to simulate copying the template were clear and standard.

2. **Step 2: Following README's Instructions**
   - **Action**: README instructions specify two actions: click "Use this template" (already simulated) and run `./install.sh`. Ran `./install.sh`.
   - **Result**: Worked exactly as written. The hook installer automatically recognized the local binaries cached in `.slopnet/bin`, bypassed the downloads, and installed the parallel Lefthook config and the pre-commit/post-commit shims.
   - **Moment of Confusion**: None. The terminal output was clean and descriptive.

3. **Step 3: Running `./doctor.sh`**
   - **Action**: Ran `./doctor.sh`.
   - **Result**: Ran successfully. All local status checks (hooks, engine, checks, manifest, CI workflow, register) passed with `[OK]`. The branch protection check printed `[??] Can't check from here — Turn on branch protection: Settings → Branches → require the slopnet checks. This is the wall nobody can climb.`
   - **Moment of Confusion**: None. The fallback status was explained cleanly in the warning. Since we ran without a remote, the `gh` check correctly noted that it couldn't check from here.

4. **Step 4: Building the Tiny Toy App**
   - **Action**: Built a tiny toy app through three commits:
     - **Commit 1**: Created executable script `hello` (`#!/usr/bin/env bash\necho "hello world"`). Ran `git add hello` and `git commit -m "Add hello script"`. The pre-commit hook ran all six checks successfully in under a second (`0.99 seconds`), and the post-commit hook appended the machine line to the register.
     - **Commit 2**: Appended documentation line `Add one line of docs` to `MAP.md`. Ran `git commit -m "Update MAP docs"`. Passed all checks in `0.35 seconds`.
     - **Commit 3**: Added another documentation line `hello script -> hello` to `MAP.md`. Ran `git commit -m "Map hello script in MAP.md"`. Passed all checks in `0.37 seconds`.
   - **Result**: Commits successfully generated auto-logged register rows in `register/2026-07-28.md` via the post-commit hook.
   - **Moment of Confusion**: None. The automation felt snappy, transparent, and completely silent unless something failed.

5. **Step 5: Spinning up a Toy Orbit Repo**
   - **Action**: Followed the recipe in `SLOPNET.md`. Registered `toy-orbit` in `SLOPNET.md`'s Registry under the cooking status. Created a new directory `toy-orbit`, ran `git init`, copied the template `README.md` and `AGENTS.md` from `SLOPNET.md` into it, added a `LOG.md`, and made the first commit.
   - **Result**: Worked exactly as written.
   - **Moment of Confusion**: None. The copy-paste markdown templates inside `SLOPNET.md` were easy to follow.

6. **Step 6: Deliberate Rejection Test (Naughty Deeds)**
   - **Action 1**: Created `untitled.txt` in the main repo clone. Attempted to run `git add untitled.txt && git commit -m "Add untitled.txt"`.
     - **Rejection Message**:
       ```text
       ┃  naming ❯ 
       RULE: untitled.txt break the naming law (spaces, banned words, backup suffixes, or non-lowercase directories).
       WHY:  Messy names make files unfindable and hide which version is the real one.
       FIX:  Rename to one clear lowercase hyphenated name and restage; the operator owns all naming.
       
       exit status 1
       ```
   - **Action 2**: Force-added a `.DS_Store` file and attempted to commit it.
     - **Rejection Message**:
       ```text
       ┃  junk ❯ 
       RULE: .DS_Store are junk files that must never be committed.
       WHY:  Junk files bloat the repo, leak local paths, and cause pointless conflicts.
       FIX:  Unstage with git rm --cached <file>; .gitignore already ignores these.
       
       exit status 1
       ```
   - **Experience & Sentiment**: The rejection messages were extremely concise and helpful. The three-line `RULE / WHY / FIX` format tells you exactly what failed, why it's not allowed, and the exact git commands or renaming rules to resolve the issue. There was no confusing clutter or log dumps.

---

## Verdict

- **Total Time**: Approximately 15 minutes.
- **One-line Verdict**: Yes, a ten-year-old could easily set this up and follow the instructions.
