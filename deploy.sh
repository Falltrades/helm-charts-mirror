#!/bin/bash

set -e

# Define the list of charts to fetch
CHARTS=("bitnamicharts/keycloak" "bitnamicharts/elasticsearch" "bitnamicharts/apache")

helm registry login registry-1.docker.io --username "${DOCKER_USERNAME}" --password "${DOCKER_PASSWORD}"

for CHART in "${CHARTS[@]}"; do
    CHART_NAME=$(basename "$CHART")
    mkdir -p ./public/$CHART_NAME

    # Get authentication token
    TOKEN=$(curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$CHART:pull" | jq -r .token)

    # Fetch latest 10 versions
    LATEST_VERSIONS=$(curl -s -H "Authorization: Bearer $TOKEN" "https://registry-1.docker.io/v2/$CHART/tags/list" | \
      jq -r '.tags | map(select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))) | sort_by(split(".") | map(tonumber)) | reverse | .[:10] | @sh')

    # Download each version
    for VERSION in $LATEST_VERSIONS; do
        VERSION=$(echo "$VERSION" | tr -d "'")  # Remove single quotes added by jq
        helm pull oci://registry-1.docker.io/$CHART --version "$VERSION" --destination ./public/$CHART_NAME
    done

    # Fetch the existing index.yaml if availableav
    INDEX_URL="https://${GITHUB_REPOSITORY_OWNER}.github.io/$(basename $GITHUB_REPOSITORY)/${CHART_NAME}"
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$INDEX_URL/index.yaml")

    if [ "$HTTP_STATUS" -eq 200 ]; then
        curl -o ./public/$CHART_NAME/index.yaml "$INDEX_URL/index.yaml"
        for TGZ in $(grep -o 'http.*tgz' ./public/$CHART_NAME/index.yaml); do
            curl --output-dir ./public -O "$TGZ"
        done
        helm repo index ./public/$CHART_NAME --url "$INDEX_URL" --merge ./public/$CHART_NAME/index.yaml
    else
        helm repo index ./public/$CHART_NAME --url "$INDEX_URL"
    fi
done
