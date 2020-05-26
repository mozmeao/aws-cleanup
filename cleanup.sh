#!/usr/bin/env bash
set -euo pipefail

OWNER=$(aws sts get-caller-identity | jq -r .Account)
CUTOFF_DATE=$(date +%Y-%m-%d --date="-30 days")
REGIONS=$(aws ec2 describe-regions | jq -r .Regions[].RegionName)
DRY_RUN=true

total_snapshots_removed=0
total_snapshots_size=0

while getopts ":f" opt; do
    case ${opt} in
        f)
            DRY_RUN=false
            ;;
    esac
done

for region in ${REGIONS};
do
    echo " ➤ Scanning region ${region}"
    TO_REMOVE=$(
        aws ec2 describe-snapshots --owner-ids="${OWNER}" --region="${region}" | \
            jq -r ".Snapshots[] | select(.StartTime|split(\"T\")[0] < \"${CUTOFF_DATE}\") | .SnapshotId" )

    for snapshot in ${TO_REMOVE};
    do
        total_snapshots_removed=$((total_snapshots_removed+1))
        CMD="aws ec2 delete-snapshot --snapshot-id \"${snapshot}\""
        if [ "${DRY_RUN}" = true ];
        then
            echo "   ➤ Removing ${snapshot} (dry-run)"
        else
            echo "   ➤ Removing ${snapshot}"
            ${CMD}
        fi
    done
done

echo " ➤ Deleted ${total_snapshots_removed} snapshots"
