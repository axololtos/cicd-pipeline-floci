#!/bin/sh
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  curl -sf http://localhost:8080/ >/dev/null && exit 0
  sleep 5
done
exit 1
