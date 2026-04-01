#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Run chart-testing (ct) lint on changed charts."
    echo ""
    echo "Options:"
    echo "  -a, --all     Lint all charts, not just changed ones"
    echo "  -h, --help    Show this help message"
}

LINT_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--all)
            LINT_ALL=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if ! command -v docker &> /dev/null; then
    echo "Error: docker is required but not installed."
    exit 1
fi

echo "Running chart-testing lint..."

CT_ARGS="--config ct.yaml"
if [ "$LINT_ALL" = true ]; then
    CT_ARGS="${CT_ARGS} --all"
fi

docker run --rm \
    -v "${REPO_ROOT}:/work" \
    -w /work \
    quay.io/helmpack/chart-testing:latest \
    ct lint ${CT_ARGS}

echo "Lint passed!"
