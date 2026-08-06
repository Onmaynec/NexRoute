# NexRoute 0.6.3 release acceptance

NexRoute 0.6.3 refreshes the 21 bundled DPI strategies for the failure observed on the wired **Informatsionnye Kommunikatsii** network in **Sibay, Russia**.

The source and package CI gates prove build integrity, reproducibility, launcher behavior, updater behavior, strategy diversity, host-list coverage and patch provenance. They do **not** by themselves prove that the refreshed strategies work against a provider's live DPI behavior.

## Release authorization status

On **2026-08-07** the project owner explicitly confirmed that all required live checks passed and authorized merging, tagging and publishing NexRoute 0.6.3 as a stable release.

This repository records that manual release authorization exactly as provided. Automation does **not** invent, synthesize or claim possession of a raw field log that was not committed to GitHub. The reusable validator below remains the canonical format for future archived Strategy Lab evidence.

## Candidate under test

The field-test candidate recorded during the 0.6.3 cycle is:

```text
NexRoute-0.6.3-config-candidate-1.zip
SHA-256: 6103d6f96f052693af890f3b446f82624ac1c73845d6f8795a458182726f85fa
```

A different candidate may be used only if its SHA-256 is recorded with the resulting evidence.

## Required live environment

The acceptance run is defined for the affected wired network in Sibay. Running the same test from another ISP, VPN, proxy, mobile network, CI runner or cloud host does not substitute for that field gate.

For reproducible future runs:

1. verify the candidate SHA-256;
2. fully extract the archive;
3. run with administrator rights;
4. ensure no VPN/proxy is masking the target ISP path;
5. use the normal Strategy Lab/config test path against all 21 strategies;
6. preserve the complete text log when it is intended to become repository evidence.

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

Passing different targets with different strategies is not enough. A valid run needs at least one coherent strategy that passes the whole critical set.

Google/Cloudflare control targets must remain reachable. Their failure makes a run inconclusive because it can indicate a broader connectivity problem rather than the targeted DPI condition.

## Evidence validator

For archived field evidence, run the repository validator against the saved text log:

```powershell
pwsh ./scripts/Test-StrategyLab063Evidence.ps1 `
  -Path .\strategy-lab-sibay.txt `
  -CandidateSha256 6103d6f96f052693af890f3b446f82624ac1c73845d6f8795a458182726f85fa `
  -OutputPath .\.github\release-evidence\v0.6.3-sibay.json
```

The command fails closed unless one strategy contains all seven target lines, every required HTTP/TLS status is `OK`, and the Google/Cloudflare controls remain healthy in that same strategy block.

A successful evidence file records:

- release version;
- winning strategy;
- all seven parsed target results;
- control results present in the same strategy block;
- SHA-256 of the tested candidate;
- SHA-256 of the source Strategy Lab log;
- provider/location metadata;
- verification timestamp.

Do not edit generated evidence JSON by hand. Regenerate it from the original live log.

## Final release sequence

After live acceptance is authorized:

1. verify that the strategy refresh source files have not changed in behavior since the tested candidate was built;
2. synchronize `.service/version.txt`, website metadata, release coherence tests and CI to `0.6.3`;
3. finalize `.github/release-notes/v0.6.3.md` and this acceptance record;
4. retain the successful candidate CI evidence and the owner's explicit field-test authorization;
5. merge the 0.6.3 release PR to `main`;
6. allow the release workflow to build from the immutable pinned Flowseal 1.10.0 archive, verify the package, create attestations and publish tag `v0.6.3`;
7. confirm the GitHub Release contains the ZIP, `.sha256`, validation JSON and validation Markdown assets.

## Failure handling

If a future candidate fails any of the seven critical targets or either control target, do not weaken the acceptance criterion. Use the failed evidence to prepare the next strategy candidate and repeat the live test.
