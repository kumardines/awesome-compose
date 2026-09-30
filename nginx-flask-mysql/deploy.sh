#!/usr/bin/env bash
set -Eeuo pipefail

: "${BUILD_NUMBER:?Run this script from Jenkins}"

export COMPOSE_PROJECT_NAME=assessment
APP_DIR="$PWD"
STATE_DIR=/var/lib/jenkins/assessment-release-state
PREVIOUS="$STATE_DIR/current"

mkdir -p "$STATE_DIR" reports

check_http() {
    local attempt
    for attempt in {1..12}; do
        if curl --fail --silent --show-error --max-time 5 \
            http://127.0.0.1/ > reports/application-response.html; then
            return 0
        fi
        sleep 3
    done
    return 1
}

deploy_candidate() {
    docker compose up -d --no-build --wait --wait-timeout 90 \
        || return 1
    check_http || return 1
}

if deploy_candidate; then
    echo "DEPLOYMENT VERIFIED: build $BUILD_NUMBER"

    RELEASE="$STATE_DIR/release-$BUILD_NUMBER"
    mkdir -p "$RELEASE"
    cp compose.yaml "$RELEASE/compose.yaml"

    echo 'services:' > "$RELEASE/images.yaml"

    for service in backend proxy; do
        container_id="$(docker compose ps -q "$service")"
        image_id="$(docker inspect --format '{{.Image}}' "$container_id")"
        release_tag="assessment-${service}:release-${BUILD_NUMBER}"

        docker tag "$image_id" "$release_tag"

        printf '  %s:\n    image: %s\n' \
            "$service" "$release_tag" >> "$RELEASE/images.yaml"

        echo "SAVED: $service $release_tag $image_id"
    done

    printf '%s\n' "$BUILD_NUMBER" > "$RELEASE/build-number"
    ln -sfn "$RELEASE" "$STATE_DIR/current.next"
    mv -Tf "$STATE_DIR/current.next" "$PREVIOUS"

    docker compose ps > reports/deployment-status.txt
    echo "HEALTHY RELEASE SAVED: build $BUILD_NUMBER"
    exit 0
fi

echo "DEPLOYMENT VERIFICATION FAILED: build $BUILD_NUMBER"

docker compose ps -a > reports/failed-deployment-status.txt || true
docker compose logs --no-color --tail=100 \
    > reports/failed-deployment-logs.txt 2>&1 || true

if [ ! -f "$PREVIOUS/images.yaml" ]; then
    echo "ROLLBACK UNAVAILABLE: no saved healthy release"
    exit 1
fi

previous_build="$(cat "$PREVIOUS/build-number")"
echo "ROLLBACK STARTED: restoring release $previous_build"

if docker compose \
    --project-directory "$APP_DIR" \
    -f "$PREVIOUS/compose.yaml" \
    -f "$PREVIOUS/images.yaml" \
    up -d --no-build --pull never --no-deps --force-recreate \
    --wait --wait-timeout 90 backend proxy; then

    if check_http; then
        docker compose \
            --project-directory "$APP_DIR" \
            -f "$PREVIOUS/compose.yaml" \
            -f "$PREVIOUS/images.yaml" \
            ps > reports/rollback-status.txt

        cat reports/rollback-status.txt
        echo "ROLLBACK SUCCESS: release $previous_build is responding"
        exit 1
    fi
fi

echo "ROLLBACK FAILED: inspect container logs"
exit 1
