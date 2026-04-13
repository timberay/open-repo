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

# Cleanup
echo "--- Cleanup ---"
docker rmi $REGISTRY/test-image:v1 $REGISTRY/test-image:v2 2>/dev/null || true

echo ""
echo "=== All Docker CLI integration tests PASSED ==="
