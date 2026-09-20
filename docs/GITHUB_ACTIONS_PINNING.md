# GitHub Actions pinning policy

NexRoute 0.6.4 treats every external GitHub Action as a release supply-chain dependency.

## Required form

External actions in `.github/workflows/*.yml` must use an immutable 40-character commit SHA. A human-readable action name and semantic version comment must remain on the same line, for example:

```yaml
uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # actions/checkout v6.1.0
```

Tags, branches and shortened commit ids are rejected. Local actions referenced through `./...` are outside this external-action allowlist.

## Enforcement

`scripts/Test-GitHubActionsPinning.ps1` contains the reviewed allowlist of action name, semantic version and exact commit SHA. Repository validation and Pester tests fail closed when they find:

- a mutable tag or branch;
- an unknown external action;
- a full SHA different from the reviewed allowlist entry;
- a missing or mismatched human-readable version comment.

This means changing only a workflow line is intentionally insufficient. The allowlist update is part of the reviewable dependency change.

## Updating an action

1. Identify the intended upstream action release from the action's official repository.
2. Resolve that release/tag to the exact full commit SHA in the official repository.
3. Review the upstream release notes and the diff from the currently pinned commit, including permission or runtime changes.
4. Update the workflow `uses:` value to the new 40-character SHA and update the adjacent semantic-version comment.
5. Update the matching entry in `scripts/Test-GitHubActionsPinning.ps1`.
6. Run `./scripts/Test-GitHubActionsPinning.ps1` and the Pester suite.
7. Let the pull-request validation workflow exercise every changed workflow path before merge.
8. For release/provenance actions, verify that required `id-token`, `attestations`, `artifact-metadata`, `contents` and other release permissions remain no broader than necessary and still support the signed release flow.

Do not bypass the validator by adding a new action to the allowlist without reviewing its exact commit. The semantic-version comment is documentation; the SHA is the executable trust boundary.

## Current 0.6.4 reviewed action set

The machine-readable source of truth is `scripts/Test-GitHubActionsPinning.ps1`. It covers checkout, Node setup, artifact upload, build attestation and GitHub Pages configure/upload/deploy actions used by the repository workflows.
