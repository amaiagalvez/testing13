#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

npmInstall(){
    local package="$1"

    remove_path node_modules || return 1
    remove_path package-lock.json

    ensure_dirs

    docker_node "npm install" || return 1

    bash "$SCRIPT_DIR/npmRunProd.sh" "$package"
}

pull_image "node:$NODE_VERSION"
run_tool npmInstall "${1:-}" "$PACKAGES"
