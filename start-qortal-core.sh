#!/bin/bash
# Desktop launchers and cron do not guarantee a working directory.
cd "${QORTAL_DIR:-${HOME}/qortal}" || exit 1
exec ./start.sh "$@"
