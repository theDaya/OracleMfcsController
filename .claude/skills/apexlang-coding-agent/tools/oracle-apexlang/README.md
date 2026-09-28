# Vendored from Oracle's APEXlang skill

Source: <https://github.com/oracle/skills/tree/main/apex/apexlang>
Licence: Universal Permissive License v1.0 — see `LICENSE.txt`.
Copyright (c) 2025 Oracle and/or its affiliates.

Taken unmodified. Two things are vendored, and nothing else from that skill is.

## `query-valid-props.mjs`

Reads the **APEX compiler's own property metadata** out of an installed SQLcl, so a block's
valid properties can be asked for rather than inferred. Needs `node` and SQLcl on PATH;
nothing else, and no network.

```bash
node query-valid-props.mjs --component region --group edit
node query-valid-props.mjs --component savedReport --component-type-id 7050
node query-valid-props.mjs --component column --parent region --list
```

Component names repeat across contexts, so an ambiguous name asks for `--parent`,
`--component-type-id` or `--when`. `--json` emits machine output.

Note what it reports: requiredness and the *conditions* that gate a property. Several
things that look flatly rejected are conditional ones whose condition is unmet —
`pageItemsToSubmit` is `when (type FEATURES [AJAX_ITEMS_TO_SUBMIT])`, not forbidden.

## `validator-fix-recipes.json`

119 validator error codes, each with a cause and a deterministic fix.

```bash
node -e "console.log(JSON.stringify(require('./validator-fix-recipes.json').recipes['ACL_ROLE_DECLARATION_REQUIRED_001'],null,2))"
```

## Refreshing these

Re-copy from the upstream repo; there are no local edits to preserve. If the tool stops
resolving metadata, check SQLcl on PATH first — it prints the build it read
(`build=26.1.0+3102`) on every run, and a mismatch with the target instance is worth
noticing before trusting the answer.
