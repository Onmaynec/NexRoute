# Strategy Lab ranking model

NexRoute 0.6.4 replaces the legacy one-shot synthetic score with an explainable repeated-observation ranking model.

## Measurement contract

Each selected strategy is tested for three rounds. The current Strategy Lab probe records HTTPS endpoint outcomes for built-in targets plus enabled Service Matrix targets. GitHub is treated as a control target. Optional HTTP latency, packet-loss, jitter and throughput values are recorded only when the underlying probe returns them.

A missing measurement is `null` / unavailable. It is never converted to zero.

## Eligibility before scoring

A strategy is ranked only when all of the following are true:

- the strategy started;
- at least six measured non-control observations exist;
- at least one critical-service target exists;
- each measured critical target has at least two observations;
- a control target exists with at least two observations;
- every measured control observation passed.

If any condition is not satisfied, `rankingState` is `inconclusive`, `score` is null and `inconclusiveReason` explains why. Inconclusive candidates are never placed ahead of eligible candidates.

A control failure is intentionally not scored as a strategy failure because it can indicate a general connectivity problem that prevents Strategy Lab from attributing the failure to the tested strategy.

## Score

For eligible candidates the normalized score uses these weights:

| Component | Weight |
| --- | ---: |
| Critical-service availability | 60% |
| Secondary-target availability | 10% |
| Repeated-observation stability | 20% |
| Optional telemetry | 10% |

Optional telemetry is itself the average of the available normalized latency, packet-loss, jitter and throughput components. Missing telemetry components are excluded and the available score weights are renormalized. This prevents an unsupported or missing throughput/latency probe from becoming a synthetic zero.

Controls are a gate and do not add score.

## Stability

For every non-control target with at least two measurements, Strategy Lab calculates consistency from its repeated pass/fail history. Always-pass and always-fail target histories are stable; alternating or partial 1-of-3 / 2-of-3 histories receive a lower stability value. Availability still distinguishes a consistently failing target from a consistently passing one.

This separation makes the ranking prefer a consistently good strategy over a similarly available but flapping strategy without hiding actual pass rate.

## Explainability

Each history result stores:

- critical, secondary, control and overall availability percentages;
- stability and optional telemetry scores;
- observation and control-observation counts;
- pass/measurement counts and pass rate for every measured endpoint;
- pass/measurement counts and pass rate by protocol;
- latency/loss/jitter/throughput values when measured;
- explicit readiness booleans for YouTube, Discord and Telegram;
- `inconclusiveReason` or `recommendationReason`.

The winning explanation includes the critical endpoint and control `passed/measured` evidence and, when a runner-up exists, the critical-availability, stability and normalized-score deltas.

## Deterministic tie-break

Eligible candidates are ordered by:

1. normalized score descending;
2. critical-service availability descending;
3. stability descending;
4. strategy file id/name ascending.

The final strategy-id rule makes exact ties deterministic and is called out in the winner explanation.

## History compatibility

New runs use history schema 3 and ranking schema 1. The CLI and native Dashboard understand the new fields, including `inconclusive` and winner explanations. Older history files remain readable through the legacy score display path; NexRoute does not rewrite old history into the new model.
