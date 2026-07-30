# ============================================================
# 国际化
# ============================================================
setup_i18n() {
    declare -gA STR

    if [[ $LANG == zh_CN* ]]; then
        LOG_URL="${LOG_URL_PREFIX}/${BOARD_MODEL}_cn.log"
        STR[sudo_warn]="\n\t请使用sudo来运行本指令\n"
        STR[newest]="\n\t你的系统版本已经是最新的 [%s]，无需更新\n"
        STR[backup_warn]="\n\t=================================\n\t||前注意备份好个人数据,以免发生意外\n\t=================================\n"
        STR[are_u_ready]="您希望继续执行吗？"
        STR[abort]="中止"
    else
        LOG_URL="${LOG_URL_PREFIX}/${BOARD_MODEL}_en.log"
        STR[sudo_warn]="\n\tError:  please use sudo !\n"
        STR[newest]="\n\tYour system version is already up to [%s], No need to update\n"
        STR[backup_warn]="\n\t========================================================\n\tBe sure to back up your personal data to avoid accidents\n\t========================================================\n"
        STR[are_u_ready]="Do you want to continue?"
        STR[abort]="Abort"
    fi
}
