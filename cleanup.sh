#!/usr/bin/env bash
set -euo pipefail

OWNER=$(aws sts get-caller-identity | jq -r .Account)
CUTOFF_DATE=$(date +%Y-%m-%d --date="-30 days")
REGIONS=$(aws ec2 describe-regions --region us-west-2 | jq -r .Regions[].RegionName)
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
    echo " ➤ Scanning region ${region} for snapshots before ${CUTOFF_DATE}"
    TO_REMOVE=$(
        aws ec2 describe-snapshots --owner-ids="${OWNER}" --region="${region}" | \
            jq -r ".Snapshots[] | select(.StartTime|split(\"T\")[0] < \"${CUTOFF_DATE}\") | .SnapshotId, .VolumeSize" )

    AVAILABLE_IMAGES=$(aws ec2 describe-images --owners="${OWNER}" --region="${region}")

    while read snapshot size && [ -n "${snapshot:-}" ];
    do
        # Snapshot is in use by image
        echo "${AVAILABLE_IMAGES}" | grep \"${snapshot}\" > /dev/null && \
            echo "   ♻ Skiping ${snapshot} currently in use by AMI" && continue

        total_snapshots_removed=$((total_snapshots_removed+1))
        total_snapshots_size=$((total_snapshots_size+size))
        CMD="aws ec2 delete-snapshot --region=${region} --snapshot-id ${snapshot}"
        if [ "${DRY_RUN}" = true ];
        then
            echo "   ➤ Removing ${snapshot} (dry-run)"
        else
            echo "   ➤ Removing ${snapshot}"
            ${CMD}
        fi
    done < <(echo ${TO_REMOVE} | xargs -n2)
done

MSG=" ➤ Deleted ${total_snapshots_removed} snapshots, saved ${total_snapshots_size} GB"
echo ${MSG}

if [ "${DRY_RUN}" = false ] && \
    [ -n "${SLACK_CHANNEL:-}" ] && [ "${total_snapshots_removed}" -ne "0" ]
then
    echo "Sending to Slack channel ${SLACK_CHANNEL}"
    slack-cli -t ${SLACK_TOKEN} -d "${SLACK_CHANNEL}" "${MSG}"
fi
