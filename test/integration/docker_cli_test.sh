#!/bin/bash
set -e

REGISTRY=${REGISTRY:-localhost:3000}

echo "=== Docker CLI Integration Test ==="
echo "Registry: $REGISTRY"
echo ""

# Test 1: Push an image
echo "--- Test 1: Build and push image ---"
echo "FROM alpine:latest" | docker build -t $REGISTRY/test-image:v1 -
docker push $REGISTRY/test-image:v1
echo "PASS: Push succeeded"

# Test 2: Pull the image back
echo "--- Test 2: Pull image ---"
docker rmi $REGISTRY/test-image:v1
docker pull $REGISTRY/test-image:v1
echo "PASS: Pull succeeded"

# Test 3: Push second tag (tests cross-repo mount)
echo "--- Test 3: Push second tag (mount test) ---"
docker tag $REGISTRY/test-image:v1 $REGISTRY/test-image:v2
docker push $REGISTRY/test-image:v2
echo "PASS: Second tag push succeeded (shared layers mounted)"

# Test 4: Verify catalog
echo "--- Test 4: Verify catalog ---"
CATALOG=$(curl -sf http://$REGISTRY/v2/_catalog)
echo "Catalog: $CATALOG"
echo "$CATALOG" | grep -q "test-image" || { echo "FAIL: test-image not in catalog"; exit 1; }
echo "PASS: Catalog contains test-image"

# Test 5: Verify tags
echo "--- Test 5: Verify tags ---"
TAGS=$(curl -sf http://$REGISTRY/v2/test-image/tags/list)
echo "Tags: $TAGS"
echo "$TAGS" | grep -q "v1" || { echo "FAIL: v1 not in tags"; exit 1; }
echo "$TAGS" | grep -q "v2" || { echo "FAIL: v2 not in tags"; exit 1; }
echo "PASS: Tags list correct"

# Test 6: HEAD manifest
echo "--- Test 6: HEAD manifest ---"
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" -I http://$REGISTRY/v2/test-image/manifests/v1)
[ "$HTTP_CODE" = "200" ] || { echo "FAIL: HEAD manifest returned $HTTP_CODE"; exit 1; }
echo "PASS: HEAD manifest returns 200"

# ============================================================
# Tag Protection scenarios (see 2026-04-22-tag-immutability-design.md)
# ============================================================

echo ""
echo "--- Test P1: enable semver protection on proto-img ---"
bin/rails runner 'Repository.find_or_create_by!(name: "proto-img").update!(tag_protection_policy: "semver")'
echo "PASS: policy set"

echo ""
echo "--- Test P2: initial push of v1.0.0 succeeds ---"
echo -e "FROM alpine:latest\nRUN echo protection-test-v1" | docker build -t $REGISTRY/proto-img:v1.0.0 - >/dev/null
docker push $REGISTRY/proto-img:v1.0.0 >/dev/null
echo "PASS: initial push accepted"

echo ""
echo "--- Test P3: re-push SAME digest succeeds (idempotent CI retry safety) ---"
docker push $REGISTRY/proto-img:v1.0.0 >/dev/null
echo "PASS: idempotent re-push accepted"

echo ""
echo "--- Test P4: push DIFFERENT digest to v1.0.0 is denied ---"
echo -e "FROM alpine:latest\nRUN echo protection-test-v2-DIFFERENT" | docker build -t $REGISTRY/proto-img:v1.0.0 - >/dev/null
PUSH_OUTPUT=$(docker push $REGISTRY/proto-img:v1.0.0 2>&1 || true)
echo "$PUSH_OUTPUT" | grep -q "denied" || { echo "FAIL: expected stderr to contain 'denied', got:"; echo "$PUSH_OUTPUT"; exit 1; }
echo "PASS: CLI printed 'denied:' on protected overwrite attempt"

echo ""
echo "--- Test P5: unprotected tag (latest) can still be overwritten under semver ---"
echo -e "FROM alpine:latest\nRUN echo protection-test-latest" | docker build -t $REGISTRY/proto-img:latest - >/dev/null
docker push $REGISTRY/proto-img:latest >/dev/null
echo "PASS: latest push succeeded under semver policy"

echo ""
echo "--- Protection cleanup: reset proto-img ---"
bin/rails runner 'Repository.find_by(name: "proto-img")&.update!(tag_protection_policy: "none")'
docker rmi $REGISTRY/proto-img:v1.0.0 $REGISTRY/proto-img:latest 2>/dev/null || true
echo "PASS: protection cleanup done"

# Cleanup
echo "--- Cleanup ---"
docker rmi $REGISTRY/test-image:v1 $REGISTRY/test-image:v2 2>/dev/null || true

echo ""
echo "=== All Docker CLI integration tests PASSED ==="
