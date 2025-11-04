# Changelog

All notable changes to **AWS Cost Audit** will be documented in this file.
This project follows [Semantic Versioning](https://semver.org/) and maintains
a single source of truth via `release.sh`.

---

## v4.3.0 — 2025-11-04
### Highlights
- Robust AWS profile detection and authentication validation.
- Improved macOS/Linux cross-compatibility.
- Cleaned up argument parsing and output consistency.
### Changes
- Reworked **AWS profile validation** logic to get correct profile.
- Added dynamic **script metadata extraction** (`Name`, `Author`, `Version`).
- Fixed remaining issues between GNU and BSD/macOS date handling.
- Refined script header formatting for better readability and maintainability.
- General cleanup of output variables and defensive guards to prevent unset-variable errors.

## v4.2.0 — 2025-10-29
- Introduced Route53 and Elastic IP audit collectors:
  - Fetches hosted zones, records, and EIP associations.
  - Aggregates cost data from `route53-cost.json` and `eip-cost.json`.
- Improved macOS and Linux date handling using adaptive `date` logic.
- Fixed legacy `EU` region name handling for S3 bucket metrics.
- Enhanced summary CSV generation and cost reporting structure.
- Added visual icons and better report output consistency.

## v4.1.0 — 2025-10-28
- Fixed support for selective section execution (`--ec2`, `--dns`, etc.).
- Introduced `safe_jq` function to handle missing or invalid JSON fields.
- Fixed “No such file” errors for optional summary `.txt` files.
- Refined packaging process for macOS tar archives.
- Enhanced summary report output for modular execution modes.
- General cleanup and stability improvements.
- Changed the OUTDIR suffix to `outdir`.

## v4.0.0 — 2025-10-27
- Major modular rewrite introducing individual collectors:
  - EC2, RDS, EBS, S3, EKS, Route53, and EIP resources.
- Implemented cross-platform compatibility for BSD/macOS `date` syntax.
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
