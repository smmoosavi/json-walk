#!/bin/env bash

source "$(dirname -- "${BASH_SOURCE[0]}")/../json-walk.sh"

is_id_key=false
print_ids() {
    event=$1
    value=${2:-}

    if [[ "$event" == "key" && "$value" == "id" ]]; then
        is_id_key=true
    elif $is_id_key; then
        echo "ID: $value"
        is_id_key=false
    fi
}

json_walk "$1" print_ids