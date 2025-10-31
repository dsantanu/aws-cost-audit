# aws-cost-audit
Modular, cross-platform AWS cost auditing and FinOps toolkit — collect, analyze, and optimize cloud spend using pure Bash and the AWS CLI

## 🧱 Key Features
| Capability                       | Description                                                             |
| -------------------------------- | ----------------------------------------------------------------------- |
| 🧩 Modular Collectors            | Collect from EC2, RDS, EBS, S3, Route53, EIP, EKS, and more             |
| 📊 Summary Reports               | CSV + TAR.GZ archives for every run                                     |
| ⚙️ Selective Execution           | Run specific collectors (e.g. `--dns`, `--eip`)                         |
| 🧠 Compute Optimizer Integration | Detect and summarize AWS optimization status                            |
| 🕓 Cross-Platform Date Logic     | Works seamlessly on both macOS and Linux                                |
| 🧮 Safe I/O                      | Graceful handling of missing or partial files (`safe_jq`, `safe_count`) |
| 🧰 Dev Ergonomics                | Prebuilt `Makefile` and `justfile` for automation                       |
| 🔒 MIT Licensed                  | Open and reusable for community & enterprise use                        |

## 📦 Directory Layout (After Run)
```bash
outdir-YYYY-MM-DD/
├── cost-by-service.json
├── ec2-instances.json
├── ebs-volumes.json
├── s3-buckets.txt
├── eks-clusters.txt
├── route53-cost.json
├── elastic-ips.json
├── eip-cost.json
├── tags.json
└── summary-report.csv
```

## 🚀 Quick Start
### Prerequisites
- AWS CLI v2 configured with read-only permissions
- jq, tar, and bash 4+
- Optional: shellcheck, tput, and make or just

### Basic Run
```bash
bash aws-cost-audit.sh
```
