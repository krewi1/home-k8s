#!/bin/bash

#####################################################################
# Observability Stack Installation Script
#
# This script calls prometheus/install.sh to install:
#   - Prometheus (with Thanos sidecar)
#   - Thanos Query, Store Gateway, Compactor
#####################################################################

cd prometheus && ./install.sh
