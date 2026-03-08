#!/bin/bash
# preload-images.sh
# Pre-loads all platform component images into the kind cluster node so that
# ArgoCD GitOps deployments don't fail due to Docker Hub rate limits or
# removed Bitnami images.
#
# Bitnami stopped hosting free images on Docker Hub in Aug 2025;
# we pull from alternative public registries and retag to match what
# the Helm charts expect.

set -eo pipefail

CLUSTER="${1:-idp}"

pull_and_load() {
  local SOURCE="$1"
  local TARGET="$2"
  local DESCRIPTION="$3"

  echo "--> Pulling $DESCRIPTION ($SOURCE)..."
  docker pull "$SOURCE"

  if [ "$SOURCE" != "$TARGET" ]; then
    echo "--> Retagging as $TARGET..."
    docker tag "$SOURCE" "$TARGET"
  fi

  echo "--> Loading into kind cluster '$CLUSTER'..."
  kind load docker-image "$TARGET" --name "$CLUSTER"
  echo ""
}

echo "==> Pre-loading platform images into kind cluster '$CLUSTER'..."

# ---- Keycloak (bitnami chart expects this image) ----
pull_and_load \
  "quay.io/keycloak/keycloak:26.3.3" \
  "docker.io/bitnami/keycloak:26.3.3-debian-12-r0" \
  "Keycloak"

# ---- Keycloak wait-for-db init container ----
# Uses bitnami/os-shell for init containers; pull from the OCI Chart registry
BITNAMI_SHELL_IMAGE="docker.io/bitnami/os-shell:12"
echo "--> Pulling Bitnami OS Shell init image ($BITNAMI_SHELL_IMAGE)..."
# bitnami os-shell is still available on docker hub as a tiny image
docker pull "$BITNAMI_SHELL_IMAGE" 2>/dev/null || true
kind load docker-image "$BITNAMI_SHELL_IMAGE" --name "$CLUSTER" 2>/dev/null || true
echo ""

# ---- PostgreSQL (Bitnami chart expects this image) ----
# Use the official postgres image and retag for bitnami compatibility
pull_and_load \
  "docker.io/bitnami/postgresql:17.5.0-debian-12-r9" \
  "docker.io/bitnami/postgresql:17.5.0-debian-12-r9" \
  "PostgreSQL (bitnami)"

echo "==> Image pre-load complete!"
