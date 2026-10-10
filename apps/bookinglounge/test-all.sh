#!/usr/bin/env bash

set -euo pipefail

bookinglounge_repository="${BL_REPO:-${HOME}/projects/bookinglounge}"
gate="${bookinglounge_repository}/Backend/deploy/test-all.sh"

if [[ ! -d "${bookinglounge_repository}/.git" ]]; then
    echo "BookingLounge repository not found at ${bookinglounge_repository}; set BL_REPO to its path." >&2
    exit 66
fi

if [[ ! -x "${gate}" ]]; then
    echo "BookingLounge test gate is missing or not executable: ${gate}" >&2
    exit 66
fi

exec "${gate}" "$@"
