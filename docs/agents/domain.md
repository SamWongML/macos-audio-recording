# Domain docs

## Layout and reading rules

This is a single-context repo:

```text
CONTEXT.md            Domain glossary
docs/adr/README.md   ADR index grouped by work area
docs/adr/NNNN-*.md   Numbered decisions and their rationale
```

Before exploring the codebase, read root `CONTEXT.md`. Then use `docs/adr/README.md` to select the
ADRs touching the work area, including linked amendments and partial supersessions. The index's
area groups are navigation within one context, not separate bounded contexts.

If a domain document is missing, proceed silently. `domain-modeling` creates documents lazily as
terms or decisions are resolved.

## Vocabulary

Use the glossary's canonical terms in issue titles, hypotheses, interfaces and test names. If a
needed concept is absent, check existing usage and record a resolved term through `domain-modeling`.
Keep `CONTEXT.md` a glossary; place implementation rationale in ADRs and task requirements in tickets.

## Decisions

Surface an ADR conflict explicitly before proposing a contrary change, for example:

> Contradicts ADR-0006 (Library is a folder); worth reopening because …

Record agreed amendments or supersessions so both the old record and the index lead to the current
rule. A partial amendment keeps the unaffected decision accepted.

For new records, use the `domain-modeling` skill's format, described in
[the ADR index](../adr/README.md#adding-or-revisiting-a-decision): a short title and one to three
sentences explaining context, decision and why. Add status, alternatives or consequences only when
useful. Retain existing records' evidence and history. Use the next number after the highest
`NNNN-*.md` filename, and add the record to the appropriate area in the index.

Create an ADR only for a decision that is hard to reverse, surprising without context, and based on
a real trade-off. Investigation notes belong in `docs/investigations/`; research belongs in
`docs/research/`.
