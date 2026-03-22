# Release Checklist

Use this checklist before tagging a release candidate.

## 1. Scope and Documentation
- [ ] Roadmap/backlog checkpoint for this release is explicitly identified.
- [ ] `README.md` feature claims match current implementation.
- [ ] `SUPPORT_MATRIX.md` is reviewed and updated for any changed support boundaries.
- [ ] User-facing wording stays truthful (for example, "Quick Launch" instead of installed-app discovery unless true enumeration is implemented).

## 2. Build and Test Validation
- [ ] App builds successfully from a clean state.
- [ ] Full automated test suite is executed.
- [ ] Regression-sensitive flows are covered by passing tests (protocol fallback, stale pairing recovery, forget/remove behavior, manual IP, settings preserve connection).
- [ ] Validation summary is captured with:
  - exact command(s) run
  - build/test context (scheme/test plan/config)
  - destination (simulator/device) when available
  - executed/passed/failed/skipped counts
  - known limitations

## 3. Warning and Diagnostics Hygiene
- [ ] No new warnings introduced in release delta.
- [ ] Existing warnings are either resolved or documented with owner and follow-up phase.
- [ ] Diagnostics logging remains structured and sanitized (no raw tokens, credentials, PINs, or secret payloads).

## 4. Product Behavior Readiness
- [ ] Connection state labels/copy remain aligned with real lifecycle states.
- [ ] Capability gating prevents unsupported actions from failing late.
- [ ] Pairing timeout and unsupported-device guidance is actionable.
- [ ] Quick Launch behavior remains truthful and usable.

## 5. Accessibility and Localization Baseline
- [ ] Core icon-heavy controls retain accessibility labels/hints after recent changes.
- [ ] High-impact strings remain localized through the project mechanism.
- [ ] Dynamic Type sanity check completed for Discovery, Remote, and Settings at larger text sizes.

## 6. Security and Privacy
- [ ] Sensitive pairing/session data remains in secure storage paths.
- [ ] Forget/remove actions still clear sensitive data as intended.
- [ ] No debug UI/log output exposes sensitive values.

## 7. Release Artifacts and Traceability
- [ ] Commit(s) for the release are on the authoritative branch.
- [ ] Release notes summarize scope, risks, and known limitations.
- [ ] Evidence references are preserved (local log/artifact paths and/or CI artifact links).

## Validation Caveat Template (Use If CI Is Unavailable)
If simulator/CI is unavailable, explicitly record:
- validation was build-only or partial test execution
- CoreSimulator/device constraints encountered
- what was still verified successfully
- residual risk due to missing runtime/CI validation
