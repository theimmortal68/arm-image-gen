# custopizer/custom.d/98-unblock-services.sh
#!/bin/bash
set -x
set -e
export LC_ALL=C
source /common.sh; install_cleanup_trap
rm -f /usr/sbin/policy-rc.d || true
