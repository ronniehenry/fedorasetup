#!/usr/bin/env bash
#
# Battery service support script
# Usage: ./battserv.sh

set -euo pipefail

log() { echo -e "\n\033[1;32m==>\033[0m $*"; }

# copy service script to systemd
log "Copying service script to systemd"
sudo cp ./services/battery-threshold.service /etc/systemd/system/battery-threshold.service

# enable service to set battery charge to 80% maximum
log "Enable battery charge limit service through systemd"
sudo systemctl enable battery-threshold.service

log "Battery charge limit service setup complete."
