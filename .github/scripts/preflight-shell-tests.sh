#!/usr/bin/env bash
set -euo pipefail

bash -n DockerfileModifier.sh
bash -n resources/smbd.sh
bash -n resources/constructConf.sh
bash -n resources/constructUsers.sh
bash -n resources/banner.sh
bash -n .github/scripts/lib-retry.sh
bash -n .github/scripts/check-existing-tags.sh

echo "script_syntax_ok"
echo "preflight_shell_tests_ok"
