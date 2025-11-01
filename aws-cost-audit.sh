#!/usr/bin/env bash
# ==========================================================
# AWS Cost Optimization Data Collection Pack
# ==========================================================
# Name   : AWS Cost Audit
# Version: v4.0.0
# Author : Santanu Das (@dsantanu)
# License: MIT
# Desc   : Collects data for AWS cost and usage analysis
# ==========================================================
set -euo pipefail

# ==========================================================
# 🧠 CLI Argument Parser (v4)
# ==========================================================

AWS_PROFILE="default"
OUTDIR="./outputs-$(date +%Y-%m-%d)"
REPORT_ONLY=false
OUTFILE="aws-cost-audit-$(date +%Y%m%d).tgz"

show_help() {
cat <<EOF
🧾 AWS Cost Audit Script (v3)
Usage: $(basename "$0") [options]

Options:
  -p, --profile <name>   AWS CLI profile [default: default]
  -o, --outfile <file>   Output tar.gz filename
                         [default: aws-cost-audit-YYYYMMDD.tar.gz]
  -d, --dest <dir>       Output directory [default: ./]
  -r, --report           Only run the report generation step (skip collectors)
  -h, --help             Show this help message and exit

  Collections:
    --all         Run all collectors (default)
    --ec2         EC2 inventory + CPU metrics
    --rds         RDS inventory
    --storage     EBS + S3
    --dns         Route 53 (zones/records/cost)
    --eip         Elastic IPs
    --network     EKS + networking resources
    --tags        Resource tags
    --cost        Cost Explorer summaries
    --optimizer   Compute Optimizer enrollment check
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--profile) AWS_PROFILE="$2"; shift 2;;
    -o|--outfile) OUTFILE="$2";     shift 2;;
    -d|--dest)    OUTDIR="$2";      shift 2;;
    -r|--report)  REPORT_ONLY=true; shift ;;
    -h|--help)    show_help; exit 0;;
    *) echo "⚠️ Unknown option: $1"; show_help; exit 1;;
  esac
done

export AWS_PROFILE
mkdir -p "${OUTDIR}"

echo "👤 Using AWS profile: ${AWS_PROFILE}"
echo "📁 Output directory: ${OUTDIR}"
echo "📦 Archive name: ${OUTFILE}"
echo "📊 Report-only mode: ${REPORT_ONLY}"

# When report-only is requested, stub AWS CLI to no-op so collectors are skipped
if [[ "${REPORT_ONLY}" == true ]]; then
  echo "📈 Report-only: skipping AWS collection calls..."
  aws() { command aws --profile "${AWS_PROFILE}" "$@" >/dev/null 2>&1 || true; }
fi

# Ensure date handling remains cross-platform (macOS/Linux)
if [[ $(uname -s) == 'Darwin' ]]; then
    echo "🍎 macOS detected — using BSD-compatible date options"
    dt_1m='-v -1m'
    dt_7d='-u -v -7d'
elif [[ $(uname -s) == 'Linux' ]]; then
    echo "🐧 Linux detected — using GNU date options"
    dt_1m='-d "1 month ago"'
    dt_7d='-u -d "7 days ago"'
else
    echo "💥 Unknown OS detected!"
    echo "⚠️  Exiting for safety..."
    exit 1
fi

Start=$(date ${dt_1m} +%Y-%m-01)
End=$(date +%Y-%m-01)

# ==========================================================
# 🎛️ v4 selective collectors
# ==========================================================

# Default: run all collectors unless specific ones are given
RUN_ALL=true
RUN_EC2=false
RUN_RDS=false
RUN_STORAGE=false
RUN_DNS=false
RUN_EIP=false
RUN_NETWORK=false
RUN_TAGS=false
RUN_COST=false
RUN_OPTIMIZER=false

# Re-parse collector flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)        RUN_ALL=true; shift;;
    --ec2)        RUN_EC2=true; RUN_ALL=false; shift;;
    --rds)        RUN_RDS=true; RUN_ALL=false; shift;;
    --storage)    RUN_STORAGE=true; RUN_ALL=false; shift;;
    --dns)        RUN_DNS=true; RUN_ALL=false; shift;;
    --eip)        RUN_EIP=true; RUN_ALL=false; shift;;
    --network)    RUN_NETWORK=true; RUN_ALL=false; shift;;
    --tags)       RUN_TAGS=true; RUN_ALL=false; shift;;
    --cost)       RUN_COST=true; RUN_ALL=false; shift;;
    --optimizer)  RUN_OPTIMIZER=true; RUN_ALL=false; shift;;
    *)            break;;
  esac
done

# Function to decide if a section runs
run_sec() {
  # $1 = section name (ec2|rds|storage|dns|eip|network|tags|cost|optimizer)
  [[ "${REPORT_ONLY}" == true ]] && return 1
  [[ "${RUN_ALL}" == true ]] && return 0
  case "$1" in
    ec2) [[ "${RUN_EC2}" == true ]] && return 0 ;;
    rds) [[ "${RUN_RDS}" == true ]] && return 0 ;;
    storage) [[ "${RUN_STORAGE}" == true ]] && return 0 ;;
    dns) [[ "${RUN_DNS}" == true ]] && return 0 ;;
    eip) [[ "${RUN_EIP}" == true ]] && return 0 ;;
    network) [[ "${RUN_NETWORK}" == true ]] && return 0 ;;
    tags) [[ "${RUN_TAGS}" == true ]] && return 0 ;;
    cost) [[ "${RUN_COST}" == true ]] && return 0 ;;
    optimizer) [[ "${RUN_OPTIMIZER}" == true ]] && return 0 ;;
  esac
  return 1
}

if [[ "${REPORT_ONLY}" == true ]]; then
  echo "📈 Report-only: generating report from existing data..."
fi

echo "🗓️ Collecting data for period: ${Start} → ${End}"


# ==========================================================
# 01. Cost and Usage Summaries
# ==========================================================
if run_sec cost; then
  echo "💰 Collecting cost summaries..."
  aws ce get-cost-and-usage \
    --time-period Start=${Start},End=${End} \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --group-by Type=DIMENSION,Key=SERVICE \
    --output json > "${OUTDIR}/cost-by-service.json"

  aws ce get-cost-and-usage \
    --time-period Start=${Start},End=${End} \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --group-by Type=DIMENSION,Key=REGION \
    --output json > "${OUTDIR}/cost-by-region.json"
fi

# ==========================================================
# 02. EC2 Instances, EIPs and CPU Utilization
# ==========================================================
if run_sec ec2; then
  echo "⚙️ Collecting EC2 inventory..."
  aws ec2 describe-instances \
    --query 'Reservations[].Instances[].{
      InstanceId: InstanceId,
      InstanceType: InstanceType,
      State: State.Name,
      AZ: Placement.AvailabilityZone,
      LaunchTime: LaunchTime,
      Tags: Tags
    }' \
    --output json > "${OUTDIR}/ec2-instances.json"

  echo "📊 Collecting EC2 CPU metrics (last 7 days)..."
  for i in $(aws ec2 describe-instances --query "Reservations[].Instances[].InstanceId" --output text); do
    aws cloudwatch get-metric-statistics \
      --namespace AWS/EC2 \
      --metric-name CPUUtilization \
      --start-time "$(date ${dt_7d} +%Y-%m-%dT%H:%M:%SZ)" \
      --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --period 3600 \
      --statistics Average \
      --dimensions Name=InstanceId,Value=${i} \
      --output json > "${OUTDIR}/cpu_${i}.json"
  done
fi

# ==========================================================
# 03. Elastic IP addresses
# ==========================================================
if run_sec eip; then
echo "🌐 Collecting Elastic IP (EIP) data..."
aws ec2 describe-addresses --output json > "${OUTDIR}/elastic-ips.json"
aws ce get-cost-and-usage \
  --time-period Start=$(date -v -30d +%F),End=$(date +%F) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --filter '{"Dimensions": {"Key": "SERVICE", "Values": ["EC2 - Elastic IP Addresses"]}}' \
  --output json > "${OUTDIR}/eip-cost.json"
fi

# ==========================================================
# 04. EBS Volumes
# ==========================================================
if run_sec ebs; then
echo "💾 Collecting EBS volume data..."
aws ec2 describe-volumes \
  --query 'Volumes[].{
    VolumeId: VolumeId,
    Size: Size,
    VolumeType: VolumeType,
    State: State,
    InstanceId: (Attachments[0].InstanceId),
    Encrypted: Encrypted,
    CreateTime: CreateTime,
    Tags: Tags
  }' \
  --output json > "${OUTDIR}/ebs-volumes.json"
fi

# ==========================================================
# 05. S3 Buckets & Storage
# ==========================================================
if run_sec s3; then
echo "🪣 Listing S3 buckets..."
aws s3api list-buckets --query "Buckets[].Name" \
                       --output text | tr '\t' '\n' > "${OUTDIR}/s3-buckets.txt"

echo "📦 Collecting S3 bucket metrics (7-day average)..."
while IFS= read -r b; do
  # Skip empty lines
  [[ -z "${b}" ]] && continue
  echo "   → Checking bucket: ${b}"

  region=$(aws s3api get-bucket-location --bucket "${b}" --query 'LocationConstraint' \
                                         --output text 2>/dev/null || echo "unknown")

  # Fix legacy or null region cases
  case "${region}" in
    None|null|"") region="us-east-1" ;;
    EU) region="eu-west-1" ;;
  esac

  aws cloudwatch get-metric-statistics \
    --namespace AWS/S3 \
    --metric-name BucketSizeBytes \
    --start-time "$(date ${dt_7d} +%Y-%m-%dT%H:%M:%SZ)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --period 86400 \
    --statistics Average \
    --dimensions Name=BucketName,Value="${b}" Name=StorageType,Value=StandardStorage \
    --region "${region}" \
    --output json > "${OUTDIR}/s3-${b}-size.json" || echo "⚠️ Skipped ${b} (no metrics or access denied)"
done < "${OUTDIR}/s3-buckets.txt"
fi

# ==========================================================
# 06. RDS Databases
# ==========================================================
if run_sec rds; then
  echo "🗄️ Collecting RDS data..."
  aws rds describe-db-instances \
      --query "DBInstances[].[DBInstanceIdentifier,Engine,DBInstanceClass,AllocatedStorage,StorageType,MultiAZ,PubliclyAccessible,Status]" \
      --output json > "${OUTDIR}/rds.json"
fi

# ==========================================================
# 07. EKS Clusters & Nodegroups
# ==========================================================
if run_sec eks; then
  echo "☸️ Collecting EKS clusters..."
  aws eks list-clusters --output text > "${OUTDIR}/eks-clusters.txt"

  while read -r c; do
    aws eks describe-cluster --name "${c}" --output json > "${OUTDIR}/eks-${c}.json"
    aws eks list-nodegroups --cluster-name "${c}" --output text > "${OUTDIR}/eks-${c}-nodegroups.txt"
    while read -r ng; do
      aws eks describe-nodegroup --cluster-name "${c}" --nodegroup-name "${ng}" \
                                 --output json > "${OUTDIR}/eks-${c}-${ng}.json"
    done < "${OUTDIR}/eks-${c}-nodegroups.txt"
  done < "${OUTDIR}/eks-clusters.txt"
fi

# ==========================================================
# 08. DNS/Route53 Components
# ==========================================================
echo "📡 Collecting Route53 hosted zones data..."
aws route53 list-hosted-zones --output json > "${OUTDIR}/route53-zones.json"
aws route53 list-health-checks --output json > "${OUTDIR}/route53-health-checks.json"

echo "💥 Exporting record sets for each hosted zone..."
jq -r '.HostedZones[].Id' "${OUTDIR}/route53-zones.json" | sed 's#/hostedzone/##' | while read -r ZONE_ID; do
  echo "   → Zone ID: ${ZONE_ID}"

  aws route53 list-resource-record-sets \
    --hosted-zone-id "${ZONE_ID}" \
    --output json > "${OUTDIR}/route53-records-${ZONE_ID}.json"
done

aws ce get-cost-and-usage \
  --time-period Start=$(date -v -30d +%F),End=$(date +%F) \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --filter '{"Dimensions": {"Key": "SERVICE", "Values": ["Amazon Route 53"]}}' \
  --output json > "${OUTDIR}/route53-cost.json"

# ==========================================================
# 09. Networking Components
# ==========================================================
echo "🌐 Collecting networking resources..."
aws elbv2 describe-load-balancers --output json > "${OUTDIR}/loadbalancers.json"
aws ec2 describe-nat-gateways --output json > "${OUTDIR}/nat-gateways.json"

# ==========================================================
# 10. Tagging Coverage
# ==========================================================
echo "🏷️ Collecting resource tags..."
aws resourcegroupstaggingapi get-resources --output json > "${OUTDIR}/tags.json"

# ==========================================================
# 11. Trusted Advisor / Compute Optimizer (if enabled)
# ==========================================================
echo "🧠 Checking Compute Optimizer enrollment..."
aws compute-optimizer get-enrollment-status --output json > "${OUTDIR}/compute-optimizer-status.json" || true

# ==========================================================
# 12. Create Summary CSV
# ==========================================================
echo "📈 Generating summary report..."

SUMMARY_CSV="${OUTDIR}/summary-report.csv"
echo "Metric,Value" > "${SUMMARY_CSV}"

# --- Cost summary
TOP_SERVICES=$(jq -r '
  .ResultsByTime[0].Groups[]
  | .Keys[0] as $svc
  | (.Metrics.UnblendedCost.Amount // "0") as $amt
  | try ($amt | tonumber) catch 0
  | [$svc, .]
  | @csv
' "${OUTDIR}/cost-by-service.json" | sort -t, -k2 -nr | head -10)

echo "" >> "${SUMMARY_CSV}"
echo "Top 10 Services by Cost:" >> "${SUMMARY_CSV}"
echo "\"Service\",\"MonthlyCost(USD)\"" >> "${SUMMARY_CSV}"
echo "${TOP_SERVICES}" >> "${SUMMARY_CSV}"

# --- EC2 stats
EC2_TOTAL=$(jq '[.[] | select(.State=="running")] | length' "${OUTDIR}/ec2-instances.json")

echo "" >> "${SUMMARY_CSV}"
echo "EC2 Instances (running),${EC2_TOTAL}" >> "${SUMMARY_CSV}"

# --- EBS unattached volumes
EBS_UNATTACHED=$(jq 'map(select((.InstanceId // null) == null)) | length' "${OUTDIR}/ebs-volumes.json")
echo "Unattached EBS Volumes,${EBS_UNATTACHED}" >> "${SUMMARY_CSV}"

# --- S3 buckets
S3_BUCKETS=$(wc -l < "${OUTDIR}/s3-buckets.txt" | xargs)
echo "Total S3 Buckets,${S3_BUCKETS}" >> "${SUMMARY_CSV}"

# --- EKS clusters
EKS_COUNT=$(wc -l < "${OUTDIR}/eks-clusters.txt" | xargs)
echo "EKS Clusters,${EKS_COUNT}" >> "${SUMMARY_CSV}"

# --- Tag coverage
TAG_COUNT=$(jq '.ResourceTagMappingList | length' "${OUTDIR}/tags.json")
echo "Tagged Resources,${TAG_COUNT}" >> "${SUMMARY_CSV}"

echo "" >> "${SUMMARY_CSV}"
echo "Report generated: $(date)" >> "${SUMMARY_CSV}"

# ==========================================================

echo "✅ All collection completed!"
echo "   Quick summary available in: ${SUMMARY_CSV##*/}"

ROUTE53_COST=$(jq -r '.ResultsByTime[0].Total.UnblendedCost.Amount // 0' "${OUTDIR}/route53-cost.json" 2>/dev/null)
EIP_COST=$(jq -r '.ResultsByTime[0].Total.UnblendedCost.Amount // 0' "${OUTDIR}/eip-cost.json" 2>/dev/null)
EIP_TOTAL=$(jq '.Addresses | length' "${OUTDIR}/elastic-ips.json" 2>/dev/null)
EIP_UNATTACHED=$(jq '[.Addresses[] | select((.InstanceId == null) and (.NetworkInterfaceId == null) and (.AssociationId == null))] | length' "${OUTDIR}/elastic-ips.json" 2>/dev/null)

echo "📡 Route 53 monthly cost: ${ROUTE53_COST} USD" | tee -a "${SUMMARY_CSV}"
echo "🌐 Elastic IP monthly cost: ${EIP_COST} USD  |  Total: ${EIP_TOTAL}  |  Unattached: ${EIP_UNATTACHED}" | tee -a "${SUMMARY_CSV}"

# ==========================================================
# 📦 Final packaging (v3)
# Creates the requested .tgz from OUTDIR contents
# ==========================================================
if [[ -n "${OUTFILE}" ]]; then
  echo "📦 Packaging results into: ${OUTFILE}"
  tar -czf "${OUTFILE}" "${OUTDIR}" && mv "${OUTFILE}" "${OUTDIR}"/
  echo "✅ Archive ready: ${OUTDIR##*/}/${OUTFILE}"
fi
