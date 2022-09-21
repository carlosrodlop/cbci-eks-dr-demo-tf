#!/bin/bash

set -x
set -euo pipefail

export MC_COUNT=5
export API_TOKEN="11eddb2d96b2bcff1adc1b811f405fef71"
export ROUTE_53_DOMAIN="ci.dw22.pscbdemos.com"
export CI_NAMESPACE="cbci"

for x in $(seq 0 $(( MC_COUNT - 1))); do
    mc=mc$x
    kubectl rollout status sts "$mc" -n "$CI_NAMESPACE"
    for i in {1..3}; do
        echo "[INFO] Launching set of build number $i for $mc jobs"
        curl -X POST --user admin:${API_TOKEN} "https://$ROUTE_53_DOMAIN/$mc/job/checkpointed/build"
        curl -X POST --user admin:${API_TOKEN} "https://$ROUTE_53_DOMAIN/$mc/job/easily-resumable/build"
        curl -X POST --user admin:${API_TOKEN} "https://$ROUTE_53_DOMAIN/$mc/job/uses-agents/build"
    done
done

