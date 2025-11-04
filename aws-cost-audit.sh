#!/usr/bin/env bash
# shellcheck disable=SC2086,SC2155
# ==========================================================
# 🧾 AWS Cost Audit Script
# ==========================================================
# Name    : AWS Cost Audit
# Author  : Santanu Das (@dsantanu) | License : MIT
# Version : v4.3.0
# Desc    : AWS cost auditing & FinOps toolkit
# Supports:
#   -p, --profile  AWS CLI profile
#   -o, --out      Output tar.gz filename
#   -d, --dest     Output directory
#   -r, --report   Report-only mode (skip collectors)
#   -h, --help     Show help
# Selective collectors:
#   --all, --ec2, --rds, --storage, --dns, --eip,
#   --network, --tags, --cost, --optimizer
# ==========================================================
set -euo pipefail

# Extract metadata from header comments dynamically
get_meta() {
  awk -F':' -v key="$1" '$0 ~ "^# " key {print $2}' "$0" | xargs
}
#
NAME=$(get_meta "Name")
AUTHOR=$(get_meta "Author")
VERSION=$(get_meta "Version")

# ==========================================================
# 🎨 Color definitions (ANSI escape codes)
# ==========================================================
if ! tput colors &>/dev/null; then
  RED=""; GRN=""; YLW=""; BLU=""; CYN=""; BLD=""; NC="";
else
  RED=$(tput setaf 1)   # red
  GRN=$(tput setaf 2)   # green
  YLW=$(tput setaf 3)   # yellow
  CYN=$(tput setaf 6)   # cyan
  BLD=$(tput bold)
  NC=$(tput sgr0)
fi

# ==========================================================
# ⏱️ Timing helper
# ==========================================================
measure() {
  local section="$1"
  shift
  local start end duration
  start=$(date +%s)
  echo "▶️  Starting ${section}..."
  "$@"
  end=$(date +%s)
  duration=$((end - start))
  echo "⏱️  ${section} completed in ${duration}s"
}

# ==========================================================
# 🧰 Command helper
# ==========================================================
safe_jq() {
  local jq_args=()
  local file=""
  while [[ $# -gt 0 ]]; do
    if [[ -f "$1" ]]; then
      file="$1"; shift; break
    fi
    jq_args+=("$1"); shift
  done
  if [[ -n "${file}" ]]; then
    jq "${jq_args[@]}" "${file}" || echo "0"
  else
    #echo "${YLW}⚠️  Missing file argument to safe_jq${NC}" >&2
    echo "0"
  fi
}

safe_cat() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    cat "${file}"
  else
    #echo "${YLW}⚠️  Skipping missing text file: ${file}${NC}" >&2
    return 1
  fi
}

safe_count() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    wc -l < "${file}" | xargs
  else
    #echo "${YLW}⚠️  Skipping missing file: ${file}${NC}" >&2
    echo "0"
  fi
}

# ==========================================================
# 🛠️ Script  helper
# ==========================================================
show_help() {
cat <<EOF

${BLD}${NAME} (${VERSION})${NC}
${YLW}Usage:${NC} $(basename "$0") [options]

${BLD}General options:${NC}
  ${GRN}-p, --profile <name>${NC}   AWS CLI profile (default: default)
  ${GRN}-o, --out <file>${NC}       Output tar.gz filename
                         default: aws-cost-audit-YYYYMMDD.tgz
  ${GRN}-d, --dest <dir>${NC}       Output directory (default: ./)
  ${GRN}-r, --report${NC}           Only run the report generation step (skip collectors)
  ${GRN}-h, --help${NC}             Show this help message

${BLD}Selective collectors:${NC}
  ${CYN}--all${NC}         Run all collectors (default)
  ${CYN}--dns${NC}         Route 53 (zones/records/cost)
  ${CYN}--ec2${NC}         EC2 inventory + CPU metrics
  ${CYN}--eip${NC}         Elastic IPs (addresses + cost)
  ${CYN}--eks${NC}         EKs + NodeGroups
  ${CYN}--rds${NC}         RDS inventory
  ${CYN}--cost${NC}        Cost Explorer summaries
  ${CYN}--tags${NC}        Resource tags
  ${CYN}--network${NC}     EKS + networking resources
  ${CYN}--storage${NC}     EBS + S3
  ${CYN}--optimizer${NC}   Compute Optimizer enrollment check

${BLD}Example:${NC}
  $(basename "$0") -p prod -d outputs --ec2 --dns

EOF
}

# ==========================================================
# 🧠 Unified CLI Parser (v4)
# ==========================================================

##set -x
# --- Defaults ---
AWS_PROFILE="default"
REPORT_ONLY=false
ACCID=''
OUTDIR=''
OUTFILE=''

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

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    # === general options ===
    -p|--profile)
      if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
        AWS_PROFILE="$2"
        shift 2
      else
        echo "⚠️  Missing argument for -p|--profile"
        exit 1
      fi
      ;;
    -d|--dest)
      if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
        OUTDIR="$2"
        shift 2
      else
        OUTDIR="./"
        shift 1
      fi
      ;;
    -o|--out)
      if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
        OUTFILE="$2"
        shift 2
      else
        echo "⚠️  Missing argument for -o|--out"
        exit 1
      fi
      ;;
    -r|--report)  REPORT_ONLY=true; RUN_ALL=false; shift;;
    -h|--help)    show_help; exit 0;;

    # === collector flags ===
    --all)        RUN_ALL=true; shift;;
    --dns)        RUN_DNS=true; RUN_ALL=false; shift;;
    --ec2)        RUN_EC2=true; RUN_ALL=false; shift;;
    --eip)        RUN_EIP=true; RUN_ALL=false; shift;;
    --eks)        RUN_EKS=true; RUN_ALL=false; shift;;
    --rds)        RUN_RDS=true; RUN_ALL=false; shift;;
    --cost)       RUN_COST=true; RUN_ALL=false; shift;;
    --tags)       RUN_TAGS=true; RUN_ALL=false; shift;;
    --network)    RUN_NETWORK=true; RUN_ALL=false; shift;;
    --storage)    RUN_STORAGE=true; RUN_ALL=false; shift;;
    --optimizer)  RUN_OPTIMIZER=true; RUN_ALL=false; shift;;
    *)
      echo "⚠️ Unknown option: $1"
      show_help
      exit 1;;
  esac
done

# ==========================================================
# 🔐 AWS Profile Detection & Validation (supports key + SSO)
# ==========================================================
AWS_CONFIG_FILE="${HOME}/.aws/config"
AWS_CREDENTIALS_FILE="${HOME}/.aws/credentials"

# --- Extract profile names safely ---
# From credentials (key-based)
CRED_PROFILES=$(grep '^\[' "${AWS_CREDENTIALS_FILE}" 2>/dev/null | tr -d '[]')

# From config (SSO or assume-role)
CONFIG_PROFILES=$(grep '^\[profile ' "${AWS_CONFIG_FILE}" 2>/dev/null | awk '{print $2}' | tr -d ']' || true)

# Add [default] from config if it’s the only section or actually usable (SSO or assume-role)
DEFAULT_USABLE=false
if [[ -f "${AWS_CONFIG_FILE}" ]]; then
  if awk '/^\[default\]/{in_default=1; next} /^\[/{in_default=0} in_default && /(sso_start_url|role_arn)/{found=1} END{exit !found}' "${AWS_CONFIG_FILE}"; then
    DEFAULT_USABLE=true
  fi
fi

# --- Combine usable profiles ---
ALL_PROFILES="${CRED_PROFILES} ${CONFIG_PROFILES}"
if [[ "${DEFAULT_USABLE}" == true ]] || { [[ -z "${ALL_PROFILES}" ]] && grep -q '^\[default\]' "${AWS_CONFIG_FILE}" 2>/dev/null; }; then
  ALL_PROFILES="default ${ALL_PROFILES}"
fi

# --- Cleanup and de-duplicate ---
ALL_PROFILES=$(echo "${ALL_PROFILES}" | tr ' ' '\n' | sort -u | xargs)

# --- Handle no profiles at all ---
if [[ -z "${ALL_PROFILES}" ]]; then
  echo "❌ No usable AWS profiles found."
  echo "💡 Run 'aws configure' for key-based auth, or 'aws configure sso' for SSO setup."
  exit 1
fi

# --- Validate selected profile ---
if ! grep -qw "${AWS_PROFILE}" <<< "${ALL_PROFILES}"; then
  echo "❌ Profile '${AWS_PROFILE}' not found or not usable."
  #echo "💡 Available profiles:"
  #echo "${ALL_PROFILES}" | sed 's/^/   - /'
  echo -e "💡 Either configure a [default] profile with 'aws configure',"
  echo -e "   Or specify an explicit profile using ${BLD}'-p <profile>'${NC}.\n"
  exit 1
fi

# --- Attempt STS lookup ---
ACCID=$(aws sts get-caller-identity \
           --profile "${AWS_PROFILE}" \
           --query "Account" --output text 2>/dev/null)

if [[ -z "${ACCID}" || "${ACCID}" == "None" ]]; then
  echo "⚠️  Unable to retrieve AWS account ID for profile '${AWS_PROFILE}'."
  echo "💡 If this is an SSO profile, try logging in first:"
  echo "   aws sso login --profile ${AWS_PROFILE}"
  # Not exiting immediately — some profiles (SSO) may authenticate lazily
else
  : #echo "👤 Using AWS profile: ${AWS_PROFILE} (Account: ${ACCID})"
fi

# ==========================================================
# 📤 Output parameters
# ==========================================================
[[ -z "${OUTDIR}" || "${OUTDIR}" == "./" ]] && \
OUTDIR="./${ACCID}-outdir-$(date +%Y-%m-%d)"

[[ -z "${OUTFILE}" ]] && \
OUTFILE="./${ACCID}-aws-cost-audit-$(date +%Y%m%d).tgz"

export AWS_PROFILE
mkdir -p "${OUTDIR}"

echo "👤 Using AWS profile: ${AWS_PROFILE} (Account: ${ACCID})"
echo "📁 Output directory : ${OUTDIR##*/}"
echo "📦 Archive name     : ${OUTFILE##*/}"
echo "📊 Report-only mode : ${REPORT_ONLY}"

# --- Helper: cross-platform date ---
if [[ $(uname -s) == 'Darwin' ]]; then
  echo "🍎 macOS detected — using BSD-compatible date options"
  dt_1m='-u -v -1m'
  dt_7d='-u -v -7d'
elif [[ $(uname -s) == 'Linux' ]]; then
  echo "🐧 Linux detected — using GNU date options"
  dt_1m='-u -d "30 days ago"'
  dt_7d='-u -d "7 days ago"'
else
  echo "💥 Unknown OS detected!"
  echo "⚠️ Exiting for safety..."
  exit 1
fi

start_30d=$(eval date ${dt_1m} +%Y-%m-01)
end_30d=$(date +%Y-%m-01)
echo "🗓️ Collecting data for period: ${start_30d} → ${end_30d}"

# ---- Helper: determine if section runs ---------------- ##
run_sec() {
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

## ---- 📊 Collectors ----------------------------------- ##

# ==========================================================
# 01. Cost and Usage Summaries
# ==========================================================

if run_sec cost; then
  echo "💰 Collecting cost summaries..."
  aws ce get-cost-and-usage \
    --time-period Start=${start_30d},End=${end_30d} \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --group-by Type=DIMENSION,Key=SERVICE \
    --output json > "${OUTDIR}/cost-by-service.json"

  aws ce get-cost-and-usage \
    --time-period Start=${start_30d},End=${end_30d} \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --group-by Type=DIMENSION,Key=REGION \
    --output json > "${OUTDIR}/cost-by-region.json"
fi

# ==========================================================
# 02. EC2 Instances and CPU Utilization
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
  for i in $(aws ec2 describe-instances \
                     --query "Reservations[].Instances[].InstanceId" \
                     --output text\
            ); do
    aws cloudwatch get-metric-statistics \
      --namespace AWS/EC2 \
      --metric-name CPUUtilization \
      --start-time "$(eval date ${dt_7d} +%Y-%m-%dT%H:%M:%SZ)" \
      --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --period 3600 \
      --statistics Average \
      --dimensions Name=InstanceId,Value=${i} \
      --output json > "${OUTDIR}/cpu_${i}.json"
  done
fi

# ==========================================================
# 03. EBS Volumes and S3 Buckets
# ==========================================================
if run_sec storage; then
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

  echo "🪣 Listing S3 buckets..."
  aws s3api list-buckets --query "Buckets[].Name" --output text | tr '\t' '\n' > "${OUTDIR}/s3-buckets.txt"

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
      --start-time "$(eval date ${dt_7d} +%Y-%m-%dT%H:%M:%SZ)" \
      --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --period 86400 \
      --statistics Average \
      --dimensions Name=BucketName,Value="${b}" Name=StorageType,Value=StandardStorage \
      --region "${region}" \
      --output json > "${OUTDIR}/s3-${b}-size.json" || echo "⚠️ Skipped ${b} (no metrics or access denied)"
  done < "${OUTDIR}/s3-buckets.txt"
fi

# ==========================================================
# 04. RDS Databases
# ==========================================================
if run_sec rds; then
  echo "🗄️ Collecting RDS data..."
  aws rds describe-db-instances \
    --query "DBInstances[].[DBInstanceIdentifier,Engine,DBInstanceClass,AllocatedStorage,StorageType,MultiAZ,PubliclyAccessible,Status]" \
    --output json > "${OUTDIR}/rds.json"
fi

# ==========================================================
# 05. EKS Clusters & Nodegroups
# ==========================================================
if run_sec eks; then
  echo "☸️ Collecting EKS clusters..."
  aws eks list-clusters --output text > "${OUTDIR}/eks-clusters.txt"

  while read -r c; do
    aws eks describe-cluster --name "${c}" --output json > "${OUTDIR}/eks-${c}.json"
    aws eks list-nodegroups --cluster-name "${c}" --output text > "${OUTDIR}/eks-${c}-nodegroups.txt"

    while read -r ng; do
      aws eks describe-nodegroup --cluster-name "${c}" --nodegroup-name "${ng}" --output json > "${OUTDIR}/eks-${c}-${ng}.json"
    done < "${OUTDIR}/eks-${c}-nodegroups.txt"
  done < "${OUTDIR}/eks-clusters.txt"
fi

# ==========================================================
# 06. Networking Components
# ==========================================================
if run_sec network; then
  echo "🌐 Collecting networking resources..."
  aws elbv2 describe-load-balancers --output json > "${OUTDIR}/loadbalancers.json"
  aws ec2 describe-nat-gateways --output json > "${OUTDIR}/nat-gateways.json"
fi

# ==========================================================
# 07. DNS/Route53 Components
# ==========================================================
if run_sec dns; then
  echo "📡 Collecting Route53 hosted zones data..."
  aws route53 list-hosted-zones --output json > "${OUTDIR}/route53-zones.json"
  aws route53 list-health-checks --output json > "${OUTDIR}/route53-health-checks.json"

  echo "💥 Exporting record sets for each hosted zone..."
  safe_jq -r '.HostedZones[].Id' "${OUTDIR}/route53-zones.json" | sed 's#/hostedzone/##' | while read -r ZONE_ID; do
    echo "   → Zone ID: ${ZONE_ID}"
    aws route53 list-resource-record-sets \
      --hosted-zone-id "${ZONE_ID}" \
      --output json > "${OUTDIR}/route53-records-${ZONE_ID}.json"
  done

  aws ce get-cost-and-usage \
    --time-period Start=$(eval date ${dt_1m} +%F),End=$(date +%F) \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --filter '{"Dimensions": {"Key": "SERVICE", "Values": ["Amazon Route 53"]}}' \
    --output json > "${OUTDIR}/route53-cost.json"
fi

# ==========================================================
# 08. Elastic IP addresses
# ==========================================================
if run_sec eip; then
  echo "🌐 Collecting Elastic IP (EIP) data..."
  aws ec2 describe-addresses --output json > "${OUTDIR}/elastic-ips.json"
  aws ce get-cost-and-usage \
    --time-period Start=$(eval date ${dt_1m} +%F),End=$(date +%F) \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --filter '{"Dimensions": {"Key": "SERVICE", "Values": ["EC2 - Elastic IP Addresses"]}}' \
    --output json > "${OUTDIR}/eip-cost.json"
fi

# ==========================================================
# 09. Tagging Coverage
# ==========================================================
if run_sec tags; then
  echo "🏷️ Collecting resource tags..."
  aws resourcegroupstaggingapi get-resources --output json > "${OUTDIR}/tags.json"
fi

# ==========================================================
# 10. Trusted Advisor / Compute Optimizer (if enabled)
# ==========================================================
if run_sec optimizer; then
  echo "🧠 Checking Compute Optimizer enrollment..."
  aws compute-optimizer get-enrollment-status --output json > "${OUTDIR}/compute-optimizer-status.json" || true
fi

# ==========================================================
# Summary + Packaging
# ==========================================================
echo "📈 Generating summary report..."

SUMMARY_CSV="${OUTDIR}/aws-summary-report.csv"
echo "Metric,Value" > "${SUMMARY_CSV}"

# --- Cost summary
TOP_SERVICES=$(safe_jq -r '
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
EC2_TOTAL=$(safe_jq '[.[] | select(.State=="running")] | length' "${OUTDIR}/ec2-instances.json")

echo "" >> "${SUMMARY_CSV}"
echo "EC2 Instances (running),${EC2_TOTAL}" >> "${SUMMARY_CSV}"

# --- EBS unattached volumes
EBS_UNATTACHED=$(safe_jq 'map(select((.InstanceId // null) == null)) | length' "${OUTDIR}/ebs-volumes.json")
echo "Unattached EBS Volumes,${EBS_UNATTACHED}" >> "${SUMMARY_CSV}"

# --- S3 buckets
S3_BUCKETS=$(safe_count "${OUTDIR}/s3-buckets.txt" | xargs)
echo "Total S3 Buckets,${S3_BUCKETS}" >> "${SUMMARY_CSV}"

# --- EKS clusters
EKS_COUNT=$(safe_count "${OUTDIR}/eks-clusters.txt" | xargs)
echo "EKS Clusters,${EKS_COUNT}" >> "${SUMMARY_CSV}"

# --- Tag coverage
TAG_COUNT=$(safe_jq '.ResourceTagMappingList | length' "${OUTDIR}/tags.json")
echo "Tagged Resources,${TAG_COUNT}" >> "${SUMMARY_CSV}"

echo "" >> "${SUMMARY_CSV}"
echo "Report generated: $(date)" >> "${SUMMARY_CSV}"

ROUTE53_COST=$(safe_jq -r '.ResultsByTime[0].Total.UnblendedCost.Amount // 0' "${OUTDIR}/route53-cost.json" 2>/dev/null)
EIP_COST=$(safe_jq -r '.ResultsByTime[0].Total.UnblendedCost.Amount // 0' "${OUTDIR}/eip-cost.json" 2>/dev/null)
EIP_TOTAL=$(safe_jq '.Addresses | length' "${OUTDIR}/elastic-ips.json" 2>/dev/null)
EIP_UNATTACHED=$(safe_jq '[.Addresses[] | select((.InstanceId == null) and (.NetworkInterfaceId == null) and (.AssociationId == null))] | length' "${OUTDIR}/elastic-ips.json" 2>/dev/null)

if [[ "${RUN_ALL}" == true ]] || run_sec dns; then
  echo "📡 Route 53 monthly cost: ${ROUTE53_COST} USD" | tee -a "${SUMMARY_CSV}"
fi
if [[ "${RUN_ALL}" == true ]] || run_sec eip; then
  echo "🌐 Elastic IP monthly cost: ${EIP_COST} USD | Total: ${EIP_TOTAL} | Unattached: ${EIP_UNATTACHED}" | tee -a "${SUMMARY_CSV}"
else
    :
fi

# ==========================================================
# 🗃️ Final packaging (v4)
# Creates the requested .tgz from OUTDIR contents
# ==========================================================
  echo "📦 Packaging results into: ${OUTFILE}"
  tar -czf "${OUTFILE}" "${OUTDIR}"

  if [[ -f "${OUTFILE}" ]]; then
    echo "✅ Archive ready: ${OUTFILE##*/}"
  fi

exit 0
