#!/usr/bin/env bash
# Common functions for chain-node-infra scripts.
# Source this file at the top of every script:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/common.sh"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load .envrc if present and not already loaded by direnv
load_envrc() {
    if [[ -f "${REPO_ROOT}/.envrc" ]]; then
        # shellcheck disable=SC1091
        source "${REPO_ROOT}/.envrc"
        echo "[info] Loaded .envrc"
    fi
}

# Require an environment variable to be set and non-empty
require_var() {
    local var_name="$1"
    local hint="${2:-}"
    if [[ -z "${!var_name:-}" ]]; then
        echo "[error] ${var_name} is not set."
        if [[ -n "${hint}" ]]; then
            echo "        ${hint}"
        fi
        echo "        Run: cp .envrc.example .envrc && edit .envrc"
        exit 1
    fi
}

# Require a CLI tool to be installed
require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" &>/dev/null; then
        echo "[error] '${cmd}' is required but not installed."
        exit 1
    fi
}

# Load envrc on source
load_envrc
