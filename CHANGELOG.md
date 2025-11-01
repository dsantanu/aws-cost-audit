# Changelog

All notable changes to **AWS Cost Audit** will be documented in this file.
This project follows [Semantic Versioning](https://semver.org/) and maintains
a single source of truth via `release.sh`.

---

## v4.0.0 — 2025-11-01
- Added emoji icons and user-friendly progress logging throughout.

## v3.1.1 — 2025-10-27
- Wrapped around curly braces {..} around all bash variables.

## v3.1.0 — 2025-10-27
- Introduced `--report-only` mode without new data collection.
- Ensured consistent use of `${OUTDIR}` and prevented double initialization.
- Improved summary output formatting for Route53 and EIP sections.
- Added basic emoji icons for OS detection and exit messages.
- Minor stability and path consistency improvements.
- Fixed final OUTFILE location.

## v3.0.0 — 2025-10-26
- Major CLI overhaul introducing new options:
  - `--profile / -p` → Specify AWS CLI profile.
  - `--out / -o` → Define final `.tgz` output file.
  - `--dest / -d` → Specify custom output directory.
  - `--report / -r` → Generate report-only mode.
  - `--help / -h` → Display help section.
- Added emojis and clearer section headers for readability.
- Improved consistency in output directory creation logic.
- Established groundwork for modular section execution (future v4 feature).

## v2.1.0 — 2025-10-26
- Fixed `Can't add archive to itself` error.

## v2.0.0 — 2025-10-26
- Introduced CLI Argument Parser.
- Supports General options only.

## v1.0.1 — 2025-10-25
- Added header information to the script.

## v1.0.0 — 2025-10-25
- Initial first version.
- Change to compatiable date format for both Linux and macOS.
