#!/usr/bin/env bash
set -eu
cp -R "$(dirname "$0")/files/." .
cd acme-utils && git init -q -b main && git add -A && git -c user.name=t -c user.email=t@example.com commit -qm "initial"
