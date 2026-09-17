# Show MOTD on interactive SSH and local console logins only; cap at 0.5s so a slow MOTD never delays login
if [ -t 0 ] && [ -z "$WLANPI_STATS_RUN" ]; then
    export WLANPI_STATS_RUN=1
    timeout 0.5 wlanpi-stats || true
fi
