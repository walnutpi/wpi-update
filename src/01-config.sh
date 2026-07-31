#!/bin/bash
# ============================================================
# 配置常量
# ============================================================
THIS_SCRIPT_VERSION=1.9
SERVER_DOMAIN="apt.walnutpi.com"
THIS_SCRIPT_URL="http://${SERVER_DOMAIN}//debian/wpi-update.gz"
THIS_SCRIPT_SAVE="/tmp/wpi-update.gz"
THIS_SCRIPT_FILE="/tmp/wpi-update"

RELEASE_FILE="/etc/WalnutPi-release"
LOG_URL_PREFIX="http://${SERVER_DOMAIN}/debian/release-log"
FILE_LOG_SAVE="/tmp/wpi-update-update.log"
FILE_PACKAGES="/tmp/wpi-update-packages.txt"
TMP_SOURCE_FILE_WPI="/tmp/wpi-update-source-wpi"
TMP_SOURCE_FILE="/tmp/wpi-update-source"
PATH_PATCH_LIST="/tmp/walnutpi-patch-list"
