# NexRoute 0.6.3 release acceptance

NexRoute 0.6.3 refreshes the 21 bundled DPI strategies for the failure observed on the wired **Informatsionnye Kommunikatsii** network in **Sibay, Russia**.

The source and package CI gates prove build integrity, reproducibility, launcher behavior, updater behavior, strategy diversity, host-list coverage and patch provenance. They do **not** prove that the refreshed strategies bypass the provider's live DPI behavior.

For that reason, 0.6.3 must not be merged to `main`, tagged or published as a stable GitHub Release until the live gate below passes.

## Candidate under test

The first generated field-test package is:

```text
NexRoute-0.6.3-config-candidate-1.zip
SHA-256: 6103d6f96f052693af890f3b446f82624ac1c73845d6f8795a458182726f85fa
```

A different candidate may be used only if its SHA-256 is recorded with the resulting evidence.

## Required live environment

The acceptance run must be performed on the affected wired network in Sibay. Running the same test from another ISP, VPN, proxy, mobile network, CI runner or cloud host does not satisfy this gate.

Before testing:

1. verify the candidate SHA-256;
2. fully extract the archive;
3. run with administrator rights;
4. ensure no VPN/proxy is masking the target ISP path;
5. use the normal Strategy Lab/config test path against all 21 strategies;
6. preserve the complete text log.

## Critical targets

At least one single strategy must pass **all three** protocol checks for **all seven** targets:

| Target | Required |
| --- | --- |
| `DiscordGateway` | `HTTP:OK TLS1.2:OK TLS1.3:OK` |
| `DiscordCDN` | `HTTP:OK TLS1.2:OK TLS1.3:OK` |
| `DiscordUpdates` | `HTTP:OK TLS1.2:OK TLS1.3:OK` |
| `YouTubeWeb` | `HTTP:OK TLS1.2:OK TLS1.3:OK` |
| `YouTubeShort` | `HTTP:OK TLS1.2:OK TLS1.3:OK` |
| `YouTubeImage` | `HTTP:OK TLS1.2:OK TLS1.3:OK` |
| `YouTubeVideoRedirect` | `HTTP:OK TLS1.2:OK TLS1.3:OK` |

Passing different targets with different strategies is not enough for the release gate. The release needs at least one coherent strategy that passes the whole critical set.

Google/Cloudflare control targets should remain reachable. Their failure makes the run inconclusive because it can indicate a broader connectivity problem rather than the targeted DPI condition.

## Evidence validator

Run the repository validator against the saved text log:

```powershell
pwsh ./scripts/Test-StrategyLab063Evidence.ps1 `
  -Path .\strategy-lab-sibay.txt `
  -CandidateSha256 6103d6f96f052693af890f3b446f82624ac1c73845d6f8795a458182726f85fa `
  -OutputPath .\.github\release-evidence\v0.6.3-sibay.json
```

The command fails closed unless one strategy contains all seven target lines and every required HTTP/TLS status is `OK`.

A successful evidence file records:

- release version;
- winning strategy;
- all seven parsed target results;
- control results present in the same strategy block;
- SHA-256 of the tested candidate;
- SHA-256 of the source Strategy Lab log;
- provider/location metadata;
- verification timestamp.

Do not edit the generated evidence JSON by hand. Regenerate it from the original live log.

## Final release sequence

Only after the validator passes:

1. commit the generated evidence and the corresponding privacy-reviewed live log or its approved archive location;
2. verify that the strategy refresh source files have not changed since the tested candidate was built;
3. bump `.service/version.txt` and website metadata to `0.6.3`;
4. update `CHANGELOG.md`, `README.md`, validation coherence checks and `.github/release-notes/v0.6.3.md`;
5. run the full pull-request CI gate;
6. merge PR #48 to `main`;
7. allow the release workflow to build from the immutable pinned Flowseal 1.10.0 archive, verify online/offline package parity, create attestations and publish tag `v0.6.3`;
8. confirm the GitHub Release contains the ZIP, `.sha256`, validation JSON and validation Markdown assets.

## Failure handling

If no strategy passes all seven critical targets, do not weaken this acceptance criterion and do not publish 0.6.3 as stable. Use the failed evidence to prepare the next strategy candidate and repeat the live test.
