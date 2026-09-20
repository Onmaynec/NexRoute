# NexRoute field evidence

NexRoute 0.6.4 introduces a privacy-minimised, deterministic receipt for live Strategy Lab acceptance evidence.

## Purpose

A field-evidence receipt records only the facts needed to reproduce the release gate decision from a particular Strategy Lab log and candidate package digest. It is designed to be safe to attach to a GitHub issue or pull request without publishing the raw diagnostic log.

The receipt **does not prove** where a test was run, who ran it, which ISP was used, or that the source log itself was captured honestly. It proves that a specific source-log SHA-256 was parsed using the NexRoute gate and that one strategy satisfied the required target/control conditions.

## What is stored

The canonical receipt contains only:

- schema/product/version/gate identifiers;
- `passed` gate status;
- candidate package SHA-256;
- source-log SHA-256;
- winning strategy file name (not an absolute path);
- the fixed seven critical Discord/YouTube target identifiers;
- the fixed two control identifiers;
- HTTP/TLS 1.2/TLS 1.3 statuses for those fixed identifiers;
- parsed strategy count;
- a fixed trust-model statement;
- SHA-256 of the canonical payload.

It intentionally excludes usernames, absolute local paths, IP addresses, MAC addresses, SSIDs, provider/location labels, arbitrary user list contents, raw logs and wall-clock verification timestamps.

## Generate a receipt

```powershell
./scripts/New-StrategyLabFieldEvidence.ps1 `
  -Path ./strategy-lab.txt `
  -CandidateSha256 <64-hex-candidate-sha> `
  -OutputPath ./field-evidence.json
```

For an explicit pre-publication privacy review, add `-PrivacyReview`. The command returns the exact receipt field names plus the categories that must remain excluded. The raw log is never copied into the receipt.

## Validate a receipt

```powershell
./scripts/Test-StrategyLabFieldEvidence.ps1 `
  -ReceiptPath ./field-evidence.json `
  -SourceLogPath ./strategy-lab.txt `
  -CandidateSha256 <64-hex-candidate-sha>
```

Validation fails closed when the schema, gate, field set, target set/order, status vocabulary, candidate hash, source-log hash or canonical payload hash differs from the contract. Unknown receipt fields are rejected rather than silently ignored.

## Determinism

For identical source-log bytes, candidate SHA-256 and NexRoute version, the generator emits byte-identical UTF-8 (without BOM) JSON. There is no generated timestamp, GUID, machine path or environment-derived identity in the canonical receipt.

## Publication rule

Publish the small JSON receipt when release evidence is required. Keep the raw log private unless a maintainer deliberately decides that its contents are safe to disclose after a separate review.
