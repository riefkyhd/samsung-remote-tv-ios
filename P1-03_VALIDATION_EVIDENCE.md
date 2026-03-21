# P1-03 Validation Evidence

Date: 2026-03-21
Scope: Rename installed-app behavior to truthful Quick Launch curated shortcuts.

## Exact Commands Run

- `mcp__xcode-tools__RunAllTests`
- `mcp__xcode-tools__BuildProject`
- `mcp__xcode-tools__GetBuildLog(severity: "warning")`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available | head -n 20`

## Build/Test Context

- Xcode tools execution in local workspace.
- Build log context indicates `Debug-iphoneos` output path (device build context).

## Destination

- Simulator destination could not be enumerated because CoreSimulator service was unavailable.
- `simctl` output reported CoreSimulator connection invalid/refused.

## Results Counts

From `RunAllTests`:
- Executed: 61
- Passed: 61
- Failed: 0
- Skipped: 0
- Not Run: 0
- Expected Failures: 0

From `BuildProject`:
- Build succeeded.

From `GetBuildLog(severity: "warning")`:
- Warnings returned: 0

## Validation Type

- Automated tests/build executed.
- Build-only destination context available (`Debug-iphoneos`).
- No successful simulator/device runtime destination enumeration in this environment.

## Artifact Paths

Test summary artifact:
- `/var/folders/s9/1m3t6r0n15g60t_5czz3vl_r0000gn/T/ActionArtifacts/C6B34792-150C-443B-8735-0EDECE55001A/RunAllTests/E1A59D37-36B3-4150-900C-D9A1FB8659DF.txt`

Build log artifact:
- `/var/folders/s9/1m3t6r0n15g60t_5czz3vl_r0000gn/T/ActionArtifacts/C6B34792-150C-443B-8735-0EDECE55001A/GetBuildLog/C08810AD-E473-4579-9306-9DBC41869097.txt`

CoreSimulator limitation evidence:
- `simctl` command output in session showing CoreSimulatorService unavailable.

## Limitation Note

This is local evidence with artifact file paths and clear counts, but not CI-hosted/downloadable artifacts.
