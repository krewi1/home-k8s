#!/bin/bash

#####################################################################
# Observability Stack Uninstallation Script
#
# This script calls prometheus/uninstall.sh to remove:
#   - Thanos components
#   - Prometheus
#####################################################################

cd prometheus && ./uninstall.sh
