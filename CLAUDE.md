# CLAUDE.md — librarian

The orchestrator that turns a bookrack into ArgoCD Applications. Shared concepts (two dispatchers, lexicon, trinkets) live in the [root CLAUDE.md](../CLAUDE.md) and [docs/vocabulary.md](../docs/vocabulary.md). This file is the chart-specific entry point: what librarian is responsible for, how it is invoked, and where to read next for each topic.

## 1. Role

Given a book name and a bookrack directory, librarian emits one ArgoCD Application per spell file. The book's `index.yaml` is librarian's Helm values file. Librarian owns routing and composition; it does not interpret workload or infrastructure fields. Those flow through untouched to summon, kaster, and other trinkets.

## 2. How librarian is invoked

### 2.1 Production — bootstrap ArgoCD Application

A single Application manifest points at the librarian chart in git and names the book via the release name. ArgoCD runs helm on librarian and applies every Application it emits (app-of-apps).

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <book>
  namespace: argocd
spec:
  source:
    repoURL: <git url>
    targetRevision: <branch>
    path: librarian
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
```

Full deployment guide: [docs/usage/deploying.md](../docs/usage/deploying.md).

### 2.2 Local testing — always via Make

```
make render   book <name>    # helm template sanity-check
make snapshot book <name>    # capture expected output
make test     book <name>    # diff against snapshot
```

Do not invoke `helm template` directly for day-to-day work; Make wires the chart path, values file, and release name.

## 3. Book layout contract

```
bookrack/
  <book>/
    index.yaml              # required — passed to librarian as values
    <chapter>/
      index.yaml            # optional — chapter defaults/overrides
      <spell>.yaml          # any number; `name:` is the only required key
```

Chapters not listed in `book.chapters` are ignored. Chapter order in `book.chapters` is the deploy order. Full authoring guide: [docs/usage/bookrack.md](../docs/usage/bookrack.md).

## 4. What librarian reads at each level

Librarian honors keys at four levels: chart `values.yaml` defaults, book `index.yaml`, chapter `index.yaml`, and spell files.

| Level | Keys librarian acts on |
|-------|------------------------|
| `librarian/values.yaml` | `appParams` defaults, `argocdNamespace` |
| book `index.yaml` | `name`, `chapters`, `defaultTrinket`, `trinkets`, `appendix`, `localAppendix`, `namePrefix`, `nameSuffix`, `clusterSelector`, `projectName`, `argocdNamespace`, `appParams` |
| chapter `index.yaml` | `name`, `defaultTrinket`, `trinkets`, `appendix`, `localAppendix`, `namePrefix`, `nameSuffix`, `clusterSelector`, `projectName`, `appParams` |
| spell file | `name` (required), `namespace`, `namePrefix`, `nameSuffix`, `chart`/`path`/`repository`/`revision`/`values`, `runes`, `clusterSelector`, `projectName`, `appendix`, `localAppendix`, `appParams`, and any key that matches a registered trinket trigger |

Field-by-field reference: [docs/usage/bookrack.md](../docs/usage/bookrack.md) for book + chapter, [docs/usage/spells.md](../docs/usage/spells.md) for spell fields.

## 5. The override cascade

Librarian layers values in a fixed order; last write wins.

### 5.1 Appendix / lexicon

```
book.appendix
  → chapter.appendix
  → spell.appendix              (merged globally in Pass 1)
  → chapter.localAppendix       (Pass 2 overlay, visible to every
                                 spell in that chapter)
  → spell.localAppendix         (Pass 2 overlay, visible only to
                                 that one spell)
```

Result: a final appendix injected as `lexicon:` into every source of the spell.

### 5.2 appParams — sync / retry / annotations / finalizers

```
librarian/values.yaml  →  book  →  chapter  →  spell
                       →  each rune.appParams
                          (unless rune.appParams.noOverite: true)
```

### 5.3 trinkets registry

```
book.trinkets  →  chapter.trinkets        (merge by trinket name)
```

### 5.4 defaultTrinket

```
book.defaultTrinket  →  chapter.defaultTrinket     (full replace)
```

### 5.5 clusterSelector

```
book  →  chapter  →  spell
```

Resolved against the final lexicon via `runicIndexer` with `typeFilter="k8s-cluster"`. Fallback: `https://kubernetes.default.svc`.

### 5.6 Primary-source values — when the primary is summon

```
defaultTrinket.values  →  entire spell body
  minus: appParams, appendix, localAppendix, runes,
         every registered trinket trigger key
  plus:  injected context (spellbook, chapter, lexicon)
```

### 5.7 Primary-source values — when the spell uses chart: / path:

```
only spell.values          (default)
+ injected context         (when appParams.bookData: true)
```

### 5.8 Trinket-source values

```
spell[trinket.key]   (e.g. spell.glyphs, spell.tarot)
  + injected context  (spellbook, chapter, lexicon)
```

Book- and chapter-level values under a registered trinket key are preserved
only in that trinket source's `spellbook.<key>` and `chapter.<key>` contexts.
They are removed from every other source. This routing is generic: Librarian
does not know Tarot fields or other trinket-specific schemas.

Deeper merge semantics: [docs/design/merge-system.md](../docs/design/merge-system.md).

## 6. Shape of the emitted ArgoCD Application

```yaml
metadata:
  name: <namePrefix><spell.name><nameSuffix>
  namespace: <argocdNamespace, default "argocd">
  finalizers, annotations          # from merged appParams
spec:
  project: <projectName, default book.name>
  destination:
    server:    <from clusterSelector or https://kubernetes.default.svc>
    namespace: <spell.namespace or spell.name>
  sources:                         # fixed order
    - <primary source>             # §5.6 or §5.7
    - <trinket sources>            # §5.8, one per matching trigger key
    - <rune sources>               # external or defaultTrinket fallback
  syncPolicy: <built from merged appParams>
  ignoreDifferences: <accumulated from runes>
```

Full field reference for `appParams`, `syncPolicy`, `managedNamespaceMetadata`, `ignoreDifferences`, and `clusterSelector`: [docs/usage/deploying.md](../docs/usage/deploying.md).

## 7. Injected context

Every source's helm values receives:

- `spellbook` — cleaned book values (trinket keys, appParams, and appendix removed).
- `chapter` — current chapter dict.
- `lexicon` — the final appendix lexicon, with `.name` ensured on every entry.
External-chart sources (`chart:` / `path:`) receive the context only when `appParams.bookData: true`. Rationale and code walkthrough: [docs/design/librarian.md](../docs/design/librarian.md), [docs/design/rendering-pipeline.md](../docs/design/rendering-pipeline.md).

## 8. Publishing to the lexicon

Stand up infrastructure, declare it under `appendix.lexicon` so downstream spells can discover it dynamically:

```yaml
appendix:
  lexicon:
    my-vault:
      type: secret-store
      labels:
        default: book
      url: http://...
```

Scope follows §5.1 — book-wide via `appendix`, chapter-wide or spell-only via `localAppendix`. User-facing guide: [docs/usage/lexicon.md](../docs/usage/lexicon.md).

## 9. Worked example

Book `index.yaml` registers kaster (for the `glyphs:` key) and tarot (for `tarot:`) with summon as `defaultTrinket`:

```yaml
name: demo
chapters: [security, workflows]

defaultTrinket:
  repository: ssh://git@forgejo/runik/summon.git
  path: .
  revision: upstream

trinkets:
  kaster:
    key: glyphs
    repository: ssh://git@forgejo/runik/kaster.git
    path: .
    revision: upstream
  tarot:
    key: tarot
    repository: ssh://git@forgejo/runik/tarot.git
    path: .
    revision: upstream

appendix:
  lexicon:
    external-gateway:
      type: istio-gw
      labels:
        access: external
        default: book
      gateway: istio-system/external-gateway
```

A spell that mixes workload with summon-internal infra (`vault:`, `istio:` at the top level):

```yaml
# bookrack/demo/security/route-2fa.yaml
name: route-2fa
image:
  repository: docker.io/2fauth
  name: 2fauth
  tag: "5.6.1"
service:
  ports:
    - port: 8000
      name: http
vault:
  prolicy:
    type: prolicy
istio:
  internal:
    type: virtualService
    subdomain: r2fa
    httpRules:
      - prefix: /
        port: 8000
```

What librarian emits:

- One Application named `route-2fa`.
- One source: summon (the defaultTrinket). `vault:` and `istio:` are top-level spell keys, so summon's internal dispatcher handles them inline.
- No kaster source — the spell has no `glyphs:` key.
- No tarot source — no `tarot:` key.
- Destination: in-cluster (no `clusterSelector`).
- Injected lexicon: whatever the book defines in `appendix.lexicon`, plus any chapter/spell additions in `security/`.

A spell that triggers a tarot source instead:

```yaml
# bookrack/demo/workflows/ci.yaml
name: ci
tarot:
  reading:
    cards:
      checkout:
        uses: git-clone
      test:
        uses: run-tests
        depends: [checkout]
```

`workflows/index.yaml` may define the reusable cards under `tarot.cards`.
Librarian passes that scoped value only through the Tarot source's chapter
context; it neither consolidates nor interprets the cards. The spell has no
`image:`, `chart:`, or `path:`, so its primary source remains summon
without the `tarot:` key. A second source receives the spell's `tarot:`
invocation and the normal context.

## 10. Internals

Implementation: `librarian/templates/runik.yaml` (emit) and `librarian/templates/project.yaml` (AppProject), with helpers in `librarian/charts/common/` and `librarian/charts/runic-system/`. Full two-pass algorithm: [docs/design/librarian.md](../docs/design/librarian.md). End-to-end rendering pipeline: [docs/design/rendering-pipeline.md](../docs/design/rendering-pipeline.md).

## 11. Related docs

- [Root CLAUDE.md](../CLAUDE.md) — framework-wide concepts.
- [docs/vocabulary.md](../docs/vocabulary.md) — glossary.
- [docs/usage/bookrack.md](../docs/usage/bookrack.md) — book / chapter authoring.
- [docs/usage/spells.md](../docs/usage/spells.md) — spell types and fields.
- [docs/usage/lexicon.md](../docs/usage/lexicon.md) — lexicon / discovery.
- [docs/usage/deploying.md](../docs/usage/deploying.md) — bootstrap and sync behavior.
- [docs/design/librarian.md](../docs/design/librarian.md) — internals.
- [docs/design/merge-system.md](../docs/design/merge-system.md) — merge cascade detail.
