#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

npmRunProd(){
    clear_public
    ensure_dirs

    docker_node "npm run prod"
}

pull_image "node:$NODE_VERSION"
run_tool npmRunProd "${1:-}" "$PACKAGES" "$DEMOS"
