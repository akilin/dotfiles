#!/bin/sh
# Ring the terminal bell on the nearest ancestor process's tty (hooks have no controlling tty).
p=$$
while [ "${p:-1}" -gt 1 ]; do
  t=$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')
  if [ -n "$t" ] && [ "$t" != "?" ]; then
    printf '\a' > "/dev/$t" 2>/dev/null
    exit 0
  fi
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
done
exit 0
