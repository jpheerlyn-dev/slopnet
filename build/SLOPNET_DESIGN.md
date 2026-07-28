# SlopNet — final framework design (v0.1)

**Status:** Proposed final design — operator to approve before the repo is born.
**Author:** Claude (Fable 5), 2026-07-28, after tearing into
`SLOPNET_RESEARCH_REPORT.md`, four second opinions, and the downloaded
source of 18 candidate projects (license files read from the actual zips).
**The three red lines govern everything here:** ten-year-old simple ·
swamp-impossible · CEO-grade with zero human upkeep.

---

## 1. Verdict on the research (the tear-in)

**The report** is strong on the commodity layer (hooks, scanners, spec
kits) and honest in its failure analysis — but it flunked its own
provenance standard: it presumed licenses it never read, ranked a BSL
project on a CEO-grade steal list, and cited niche repos without adoption
evidence. Verified against the downloaded source:

| Claimed | Verified from the zip | Consequence |
|---|---|---|
| grain "MIT (Presumed)" | **NO LICENSE FILE** | All rights reserved. Code untouchable; the *ideas* (naked-except, hedge-word, echo-comment detection) get reimplemented from scratch |
| agent-guardrails MIT | MIT ✓ | Patterns liftable with attribution |
| SourceryKit BSL 1.1 | BSL 1.1 ✓ | Cut (was cut for scope anyway) |
| pydantic-ai-shields MIT | MIT ✓ | Cut for scope (in-process middleware) |
| Lefthook / Gitleaks MIT | MIT ✓ / MIT ✓ | Core dependencies, cleared |
| spec-kit / fspec MIT | MIT ✓ / MIT ✓ | Cut for scope; ideas noted |

**The four opinions** converged to near-unanimity, which is itself
signal:

- **Unanimous keeps:** Gitleaks (offline, milliseconds), Lefthook
  (parallel speed = anti-bypass), protected-path blocking, grain-style
  slop-lint, Scratch's "snap" ethos as north star.
- **Unanimous cuts:** spec-driven ceremony (fails red line 1), advisory
  files treated as enforcement (fails red line 2), copyleft/BSL deps
  (fails red line 3), in-process LLM middleware, honeyslop canaries.
- **Best individual catches:** Kimi — "who guards the guards" (nothing
  stops editing the hooks themselves) and "provable is never defined";
  GLM/Grok — local hooks are bypassable, **CI + branch protection is the
  only real wall**, and the steals are quietly Python-locked; Gemini —
  rejected commits that dump logs into an agent's context trigger
  hallucination spirals, so error output is a first-class design surface.

**Where all four were wrong, and it matters:** every reviewer cut or
ignored the register (Grok called it "session-logging theater"), and none
even mentioned the orbit model. But records and containment are two of
the operator's founding requirements — and the market survey proves
*nobody ships them*. The reviewers accurately graded the stolen parts and
unanimously missed the original ones. Conclusion: the walls are
commodity; **the register and the orbit are SlopNet's actual product.**
The fix for "theater" is not cutting the register but making it
automatic (§3.2).

---

## 2. What SlopNet is

A GitHub template repository. Two actions — click **Use this template**,
run **./install.sh** — and the workspace becomes structurally incapable
of growing slop. Three pillars:

1. **The Walls** — mechanical chokepoint enforcement (stolen, MIT-clean).
2. **The Register** — an automatic paper trail of who asked for what and
   what was done (original, proven in **REDACTED**).
3. **The Orbit** — new ideas are born in their own small repos that call
   the app; the trunk stays stable forever (original, proven in **REDACTED**
   three times before it had a name).

Enforcement architecture — four layers, one law:

| Layer | Where | Bypassable? |
|---|---|---|
| 0 — Pointers | `AGENTS.md` etc. (≤40 lines, advisory by design) | Yes — and that's fine; they point, they don't enforce |
| 1 — Local hooks | Lefthook → `checks/*.sh`, milliseconds, parallel | Yes (`--no-verify`) — they exist for speed of feedback, not for trust |
| 2 — CI | The **same** `checks/*.sh` files re-run + integrity manifest | No, once layer 3 is on — this is the wall |
| 3 — Repo settings | Branch protection + required status checks | Not from inside the repo; `doctor.sh` verifies and nags until enabled |

The trick that answers "who guards the guards": there is **one** law
source — the `checks/` directory — called identically by layer 1 and
layer 2, plus a `MANIFEST.sha256` of every check and hook. CI fails any
change to the machinery that doesn't update the manifest in the same
commit, so tampering is never silent; with branch protection on, it's
never mergeable unreviewed either.

---

## 3. The v0.1 template, file by file

```
slopnet/
├─ README.md                  # 5 lines: what it is, the two actions, nothing else
├─ AGENTS.md                  # ≤40 lines: the law for agents; points at checks/
├─ HUMANS.md                  # the human's side: prompt format, their jobs
├─ MAP.md                     # address book; starts tiny, grows with the app
├─ SLOPNET.md                 # the orbit registry + idea-repo templates
├─ install.sh                 # zero-dep bash: arms hooks, fetches pinned binaries,
│                             #   falls back to pure-shell checks if fetch fails
├─ doctor.sh                  # green-tick checklist: hooks armed? CI present?
│                             #   branch protection on? (via gh, else prints how)
├─ lefthook.yml               # layer-1 runner: parallel, milliseconds
├─ .gitleaks.toml             # offline secret patterns
├─ MANIFEST.sha256            # checksums of checks/ + hooks/ (guard the guards)
├─ checks/                    # THE single source of law — POSIX sh, no language
│  ├─ secrets.sh              #   gitleaks if present, fallback regex set if not
│  ├─ protected-paths.sh      #   frozen-list: nothing mutates slopnet machinery
│  │                          #   or paths the operator seals (their "Lego blocks")
│  ├─ naming.sh               #   naming law: bans _old/_v2/copy/final/untitled/
│  │                          #   temp/.bak/spaces; enforces case convention
│  ├─ junk.sh                 #   blocks .DS_Store, __pycache__, node_modules,
│  │                          #   *.log, editor droppings from ever being staged
│  ├─ slop-lint.sh            #   reimplemented grain ideas: naked except:pass,
│  │                          #   "simplified version" bypass phrases, echo-comments
│  └─ register.sh             #   source changed ⇒ today's register file changed
├─ hooks/                     # thin shims install.sh copies into .git/hooks
│  ├─ pre-commit              #   runs lefthook (or the checks loop directly)
│  └─ post-commit             #   AUTO-appends the machine line to the register:
│                             #   time, author, subject, files touched
├─ register/
│  └─ README.md               # the protocol; day files create themselves
├─ adapters/
│  └─ claude-code/            # settings.json + prompt auto-logger + path guard
│                             #   (ported from **REDACTED**, already proven live)
└─ .github/workflows/
   └─ slopnet.yml             # layer 2: re-run checks/* verbatim + verify manifest
```

No empty folders. Every file either enforces a slop class on day one or
arms something that does. The five human-readable files are the same five
**REDACTED** runs on — the template is **REDACTED**'s environment, generalized.

### 3.1 Design rules the reviews forced

- **Language-agnostic core.** Every v0.1 check is path/diff/grep logic in
  POSIX shell. Python/JS-specific enforcement (import-linter,
  dependency-cruiser, AST-level slop lint) ships later as auto-detected
  optional packs — never in core (Grok/GLM's polymorphism critique).
- **Errors are written for LLM readers.** Every check emits at most three
  lines: `RULE / WHY / FIX`, then exits. No log dumps — a rejected agent
  gets a next action, not a context-poisoning wall of text (Gemini's
  catch).
- **Zero-dependency floor, fast ceiling.** If the pinned gitleaks/lefthook
  binaries can't be fetched (offline, corporate proxy), install.sh wires
  the pure-shell fallbacks. Slower, still blocking. The floor never
  requires a package manager (the report's own distribution finding).
- **The register has an automatic floor.** The post-commit hook writes
  the machine line unaided; tool adapters (Claude Code today) capture the
  human's prompts verbatim; agents add prose only when they have
  something to say. Grok's "theater" dies here: the record exists even if
  every party forgets — zero human upkeep, red line 3 intact.
- **Speed budget:** the full layer-1 suite must run in under one second
  on a normal laptop or the offending check gets cut — hook latency is
  the documented #1 killer of governance (Husky's grave, every reviewer).

### 3.2 What v0.1 deliberately does NOT do

Stated openly, because CEO-grade means honest scope:

- **Semantic slop** — syntactically perfect code implementing the wrong
  business logic passes every gate (Gemini's third point). That is what
  tests and the human's UX job are for; SlopNet guards the workspace, not
  the requirements.
- **LLM-as-judge** — never, at any version. Probabilistic gates are
  unprovable and carry per-run cost forever (Kimi's red-line-3 kill).
- **Spec phases, state machines, runtime middleware** — cut per unanimous
  review.
- **Windows** — v0.1 assumes git-bash/WSL; native PowerShell parity is a
  fast-follow, not a launch gate.

---

## 4. Red-line compliance, argued

1. **TEN-YEAR-OLD SIMPLE.** Two actions to full protection. `doctor.sh`
   speaks in green ticks and plain sentences. Rule rejections are three
   lines with a FIX. The child never edits a config — defaults rule until
   the operator *chooses* to take the wheel (Scratch's low floor, wide
   walls).
2. **SWAMP-IMPOSSIBLE.** Junk, secrets, banned names, protected paths,
   silent-error patterns, and unrecorded changes are all *commit-time
   failures*, re-verified identically in CI, with machinery tampering
   caught by manifest. The honor system appears nowhere in the
   enforcement path.
3. **CEO-GRADE.** Every dependency MIT, verified from primary sources
   (grain's absence of a license caught before a line was lifted — the
   process working). The provable artifact Kimi demanded exists: the
   required green check on every PR, visible to anyone, forgeable by no
   one once branch protection is on. Upkeep: the register writes itself;
   the checks are static files; there is nothing to nurse.

---

## 5. Build plan

1. **Operator creates the `slopnet` repo** (name already ruled) — private
   until v0.1 stands, public when the doctor passes on a stranger's
   machine. First row enters **REDACTED**'s `SLOPNET.md` registry: *slopnet —
   cooking* — the framework is its own first orbit.
2. **M1 — Walls:** install.sh, checks/, lefthook.yml, CI workflow,
   manifest. Exit test: a scripted "malicious agent" (a shell script
   attempting 20 slop moves — junk files, banned names, secret commit,
   protected-path edit, naked except) goes 0-for-20.
3. **M2 — Register:** post-commit floor + protocol + Claude adapter port.
   Exit test: a full session leaves a readable day-file with zero manual
   steps.
4. **M3 — Orbit:** SLOPNET.md template + doctor.sh. Exit test: spin up a
   toy idea-repo against a toy trunk by following only the printed
   instructions.
5. **M4 — The classroom test, literally:** hand the template to one
   beginner (or one small model driving a toy app) with no coaching.
   Watch. Every point of confusion is a v0.2 bug.
6. **Graduation of SlopNet itself into public use** follows its own
   checklist — including the day **REDACTED** replaces its hand-built
   environment with the template it birthed.

## 6. Standing questions for the operator

- Approve this design as v0.1 scope? (Anything cut here can return in v0.2.)
- Create the `slopnet` GitHub repo (or authorize `gh repo create slopnet --private`)?
- The naming law defaults (kebab-case dirs, banned-word list) will be
  written by an agent — flag anything you want banned or blessed from
  day one.
