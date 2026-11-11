#!/bin/sh
# Ordinary-user fixture: publish readiness and retain the same PID in sleep.
trap '' TERM
task_unit=legion-bootstrap-probe-01234567-89ab-4cde-8fab-0123456789ab.service
printf 'SNAPSHOT_READY launcher=%s unit=%s\n' "$$" "$task_unit"
printf 'START_ACKNOWLEDGED\n'
printf 'CONTROL_READY helper=123 unit=%s address=unix:path=/run/%s/control.sock\n' "$task_unit" "${task_unit%.service}"
if [ -x /usr/bin/sleep ]; then
  exec /usr/bin/sleep 120
fi
exec /run/current-system/sw/bin/sleep 120
