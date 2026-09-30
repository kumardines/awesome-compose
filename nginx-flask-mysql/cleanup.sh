#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR=/var/lib/jenkins/assessment-release-state

if [ ! -f "$STATE_DIR/current/build-number" ]; then
    echo "Cleanup skipped: no saved healthy release."
    exit 0
fi

current="$(cat "$STATE_DIR/current/build-number")"

mapfile -t releases < <(
    find "$STATE_DIR" -mindepth 2 -maxdepth 2 \
        -type f -name build-number -exec cat {} \; |
    grep -E '^[0-9]+$' |
    sort -rn -u
)

if [ "${#releases[@]}" -eq 0 ]; then
    echo "Cleanup skipped: no release records."
    exit 0
fi

echo "Keeping the two newest healthy releases:"
printf '%s\n' "${releases[@]:0:2}"
echo "Also protecting current release: $current"

declare -A used_images=()

while IFS= read -r container; do
    [ -n "$container" ] || continue

    image_id="$(docker inspect --format '{{.Image}}' "$container")"
    image_ref="$(docker inspect --format '{{.Config.Image}}' "$container")"

    used_images["$image_id"]=1
    used_images["$image_ref"]=1
done < <(docker ps -aq)

removed=0

for release in "${releases[@]:2}"; do
    [ "$release" != "$current" ] || continue

    for service in backend proxy; do
        tag="assessment-${service}:release-${release}"

        if ! image_id="$(docker image inspect \
            --format '{{.Id}}' "$tag" 2>/dev/null)"; then
            continue
        fi

        if [ "${used_images[$tag]:-}" = 1 ] ||
           [ "${used_images[$image_id]:-}" = 1 ]; then
            echo "KEEP: $tag is associated with a container."
            continue
        fi

        echo "Eligible old release tag: $tag"

        if docker image rm "$tag"; then
            removed=$((removed + 1))
        else
            echo "KEPT: Docker refused removal of $tag."
        fi
    done
done

echo "Removed release tags: $removed"
echo "Retained backend image tags:"
docker image ls assessment-backend

echo "Retained proxy image tags:"
docker image ls assessment-proxy

echo "Active project containers:"
docker ps --filter label=com.docker.compose.project=assessment \
    --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
