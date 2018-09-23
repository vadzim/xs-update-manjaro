#!/bin/bash
#Auto Update For Manjaro Xfce by Lectrode
vsn="v3.0.1-dev"; vsndsp="$vsn 2018-09-13"
#-Downloads and Installs new updates
#-Depends: pacman, paccache, xfce4-notifyd, grep, ping
#-Optional Depends: pikaur, apacman (deprecated)
true=0; false=1; ctrue=1; cfalse=0;


conf_f='/etc/xs/auto-update.conf'
debgn=+x; # -x =debugging | +x =no debugging
set $debgn



#---Define Functions---

trouble(){ (echo;echo "#XS# `date` - $@") |tee -a $log_f; }
troublem(){ echo "XS-$@" |tee -a $log_f; }

pacclean(){
[[ ! "${conf_a[cln_1enable_bool]}" = "$ctrue" ]] && return

[[ "$(expr ${conf_a[cln_aurpkg_bool]} + ${conf_a[cln_aurbuild_bool]} + ${conf_a[cln_paccache_num]})" -gt "-1" ]] && trouble "Performing cleanup operations..."

if [[ "${conf_a[cln_aurpkg_bool]}" = "$ctrue" ]]; then
    troublem "Cleaning AUR package cache..."
    if [ -d /var/cache/apacman/pkg ]; then rm -rf /var/cache/apacman/pkg/*; fi
    if [ -d /var/cache/pikaur/pkg ]; then rm -rf /var/cache/pikaur/pkg/*; fi
fi

if [[ "${conf_a[cln_aurbuild_bool]}" = "$ctrue" ]]; then
    troublem "Cleaning AUR build cache..."
    if [ -d /var/cache/pikaur/aur_repos ]; then rm -rf /var/cache/pikaur/aur_repos/*; fi
    if [ -d /var/cache/pikaur/build ]; then rm -rf /var/cache/pikaur/build/*; fi
fi

if [[ "${conf_a[cln_paccache_num]}" -gt "-1" ]]; then
    troublem "Cleaning pacman cache..."
    paccache -rfqk${conf_a[cln_paccache_num]}
fi
}

exportconf(){
if [ ! -d `dirname $conf_f` ]; then mkdir `dirname $conf_f`; fi
echo '#Config for XS-AutoUpdate' > "$conf_f"
echo '#' >> "$conf_f"
echo '# AUR Settings #' >> "$conf_f"
echo '#aur_1helper_str: Valid options are auto,none,all,pikaur,apacman' >> "$conf_f"
echo '#aur_devel_bool:  If enabled, directs pikaur to update -git and -svn packages' >> "$conf_f"
echo '#' >> "$conf_f"
echo '# Cleanup Settings #' >> "$conf_f"
echo '#cln_1enable_bool:  Enables/disables all package cleanup' >> "$conf_f"
echo '#cln_aurpkg_bool:   Enables/disables AUR package cleanup' >> "$conf_f"
echo '#cln_aurbuild_bool: Enables/disables AUR build cleanup' >> "$conf_f"
echo '#cln_orphan_bool:   Enables/disables uninstall of uneeded packages' >> "$conf_f"
echo '#cln_paccache_num:  Number of official packages to keep (-1 to keep all)' >> "$conf_f"
echo '#' >> "$conf_f"
echo '# Flatpak Settings #' >> "$conf_f"
echo '#flatpak_1enable_bool: Check for Flatpak package updates' >> "$conf_f"
echo '#' >> "$conf_f"
echo '# Notification Settings #' >> "$conf_f"
echo '#notify_1enable_bool: Enable/Disable nofications' >> "$conf_f"
echo '#notify_lastmsg_num: Seconds before final normal notification expires (0=never)' >> "$conf_f"
echo '#notify_errors_bool: Include possible errors in notifications' >> "$conf_f"
echo '#' >> "$conf_f"
echo '# Main Settings #' >> "$conf_f"
echo '#main_ignorePackages_str: list of packages to ignore separated by spaces (in addition to pacman.conf)' >> "$conf_f"
echo '#main_logdir_str: path to the log directory' >> "$conf_f"
echo '#main_mirrorCountry_str: Countries separated by commas from which to pull updates. Default is automatic (geoip)' >> "$conf_f"
echo '#main_testSite_str: url (without protocol) used to test internet connection' >> "$conf_f"
echo '#' >> "$conf_f"
echo '# Update Settings #' >> "$conf_f"
echo '#update_downgrades_bool: Directs pacman to downgrade package if remote is older than local' >> "$conf_f"
echo '#update_keys_bool: Check for security signature/key updates' >> "$conf_f"
echo '#' >> "$conf_f"
echo '# Custom Makepkg Flags for AUR packages (requires pikaur)' >> "$conf_f"
echo '#zflag:packagename1,packagename2=--flag1,--flag2,--flag3' >> "$conf_f"
echo '#' >> "$conf_f"
echo '#' >> "$conf_f"
DEFAULTIFS=$IFS; IFS=$'\n'
for i in $(sort <<< "${!conf_a[*]}"); do
	echo "$i=${conf_a[$i]}" >> "$conf_f"
done; IFS=$DEFAULTIFS
}

#Notification Functions

killmsg(){ if [ "${conf_a[notify_1enable_bool]}" = "$ctrue" ]; then killall xfce4-notifyd; fi; }
iconnormal(){ icon=ElectrodeXS; }
iconwarn(){ icon=important; }
iconcritical(){ icon=system-shutdown; }

sendmsg(){
    if [ "${conf_a[notify_1enable_bool]}" = "$ctrue" ]; then
        DISPLAY=$2 su $1 -c "dbus-launch notify-send -i $icon XS-AutoUpdate -u critical \"$3\"" & fi
}

sendall(){
    if [ "${conf_a[notify_1enable_bool]}" = "$ctrue" ]; then
        getsessions; i=0; while [ $i -lt ${#s_usr[@]} ]; do
            sendmsg "${s_usr[$i]}" "${s_disp[$i]}" "$1"; i=$(($i+1))
        done; unset i
    fi
}

finalmsg_normal(){
    killmsg; iconnormal; sendall "$msg"; if [ ! "${conf_a[notify_lastmsg_num]}" = "0" ]; then
        sleep ${conf_a[notify_lastmsg_num]}; killmsg; fi
}

finalmsg_critical(){
    killmsg; iconcritical; sendall "Kernel and/or drivers were updated. Please restart your computer to finish"
    mv -f "$log_f" "${log_f}_`date -I`"; log_f=${log_f}_`date -I`
}

getsessions(){
    DEFAULTIFS=$IFS; IFS=$'\n\b';
    unset s_usr[@]; unset s_disp[@]; unset s_home[@]
    i=0; for sssn in `loginctl list-sessions --no-legend`; do
        IFS=' '; sssnarr=($sssn)
        actv=$(loginctl show-session -p Active ${sssnarr[0]}|cut -d '=' -f 2)
        [[ "$actv" = "yes" ]] || continue
        usr=$(loginctl show-session -p Name ${sssnarr[0]}|cut -d '=' -f 2)
        disp=$(loginctl show-session -p Display ${sssnarr[0]}|cut -d '=' -f 2)
        usrhome=$(getent passwd "$usr"|cut -d: -f6) #alt: eval echo "~$usr"
        [[  ${usr-x} && ${disp-x} && ${usrhome-x} ]] || continue
        s_usr[$i]=$usr; s_disp[$i]=$disp; s_home[$i]=$usrhome; i=$(($i+1)); IFS=$'\n\b';
    done
    if [ ${#s_usr[@]} -eq 0 ]; then sleep 5; fi
    IFS=$DEFAULTIFS; unset i; unset usr; unset disp; unset usrhome; unset actv; unset sssnarr; unset sssn
}

backgroundnotify(){ while : ; do
    getsessions; i=0; while [ $i -lt ${#s_usr[@]} ]; do
        if [ -f "${s_home[$i]}/.cache/xs/logonnotify" ]; then
            iconwarn; sleep 5; sendmsg "${s_usr[$i]}" "${s_disp[$i]}" \
                "System is updating (please do not turn off the computer)\nDetails: $log_f"
            rm -f "${s_home[$i]}/.cache/xs/logonnotify"
        fi; i=$(($i+1)); sleep 2
    done
done; }

userlogon(){
    sleep 5; if [ ! -d "$HOME/.cache/xs" ]; then mkdir -p "$HOME/.cache/xs"; fi
    if [ ! -f "$log_f" ]; then if [[ `ls "${log_d}" | grep -F "auto-update.log_" 2>/dev/null` ]]; then
        iconcritical; notify-send -i $icon XS-AutoUpdate -u critical \
            "Kernel and/or drivers were updated. Please restart your computer to finish"
    fi; else echo "This is a temporary file. It will be removed automatically" > "~/.cache/xs/logonnotify"; fi
}


#---Init Config---

#Init Defaults

typeset -A flag_a

typeset -A conf_a; conf_a=(
    [aur_1helper_str]="auto"
    [aur_devel_bool]=$ctrue
    [cln_1enable_bool]=$ctrue
    [cln_aurpkg_bool]=$ctrue
    [cln_aurbuild_bool]=$ctrue
    [cln_orphan_bool]=$ctrue
    [cln_paccache_num]=0
    [flatpak_1enable_bool]=$ctrue
    [notify_1enable_bool]=$ctrue
    [notify_lastmsg_num]=20
    [notify_errors_bool]=$ctrue
    [main_ignorepkgs_str]=""
    [main_logdir_str]="/var/log/xs"
    [main_country_str]=""
    [main_testsite_str]="www.google.com"
    [update_downgrades_bool]=$ctrue
    [update_keys_bool]=$ctrue
    #legacy
    [bool_detectErrors]=""
    [bool_Downgrades]=""
    [bool_notifyMe]=""
    [bool_updateFlatpak]=""
    [bool_updateKeys]=""
    [str_cleanLevel]=""
    [str_ignorePackages]=""
    [str_log_d]=""
    [str_mirrorCountry]=""
    [str_testSite]=""
)

shopt -s extglob # needed for validconf
validconf=@($(echo "${!conf_a[*]}"|sed "s/ /|/g"))

conf_int0="notify_lastmsg_num"
conf_intn1="cln_paccache_num"
conf_legacy="bool_detectErrors bool_Downgrades bool_notifyMe bool_updateFlatpak bool_updateKeys str_cleanLevel str_ignorePackages str_log_d str_mirrorCountry str_testSite"

#Load external config
#Basic config validation

if [ -f $conf_f ]; then
    while read line; do
        line=$(echo "$line" | cut -d ';' -f 1 | cut -d '#' -f 1)
        if echo "$line" | grep -F '=' &>/dev/null; then
            varname=$(echo "$line" | cut -d '=' -f 1)
            case $varname in
                $validconf) ;;
                *) echo "$varname"|grep -F "zflag:" >/dev/null || continue
            esac
            line=$(echo "$line" | cut -d '=' -f 2-)
            if [[ ! "$line" = "" ]]; then
                #validate boolean
                echo "$varname" | grep -F "bool" >/dev/null && if [[ ! ( "$line" = "$ctrue" || \
                    "$line" = "$cfalse" ) ]]; then continue; fi
                #validate numbers
                if echo "$varname" | grep "num" >/dev/null; then 
                    if [[ ! "$line" = "0" ]]; then let "line += 0"
                    [[ "$line" = "0" ]] && continue; fi; fi
                #validate integers 0+
                if echo "$conf_int0" | grep "$varname" >/dev/null; then 
                    if [[ "$line" -lt "0" ]]; then continue; fi; fi
                #validate integers -1+
                if echo "$conf_intn1" | grep "$varname" >/dev/null; then 
                    if [[ "$line" -lt "-1" ]]; then continue; fi; fi
                #validate aur_helper_str
                if [[ "$varname" = "aur_helper_str" ]]; then case "$line" in
                        auto|none|all|pikaur|apacman) ;;
                        *) continue
                esac; fi

                conf_a[$varname]=$line
                echo "$varname" | grep -F "zflag:" >/dev/null && \
                    flag_a[$(echo "$varname" | cut -d ':' -f 2)]="${conf_a[$varname]}"

            fi
        fi
    done < "$conf_f"; unset line; unset varname
fi
unset validconf; shopt -u extglob

#Convert legacy settings

case "${conf_a[str_cleanLevel]}" in
    high) conf_a[cln_aurpkg_bool]="$ctrue";  conf_a[cln_aurbuild_bool]="$ctrue";  conf_a[cln_paccache_num]=0 ;;
    low)  conf_a[cln_aurpkg_bool]="$cfalse"; conf_a[cln_aurbuild_bool]="$cfalse"; conf_a[cln_paccache_num]=2 ;;
    off)  conf_a[cln_aurpkg_bool]="$cfalse"; conf_a[cln_aurbuild_bool]="$cfalse"; conf_a[cln_paccache_num]=-1
esac

[[ ! "${conf_a[bool_detectErrors]}" = "" ]]  && conf_a[notify_errors_bool]="${conf_a[bool_detectErrors]}"
[[ ! "${conf_a[bool_Downgrades]}" = "" ]]    && conf_a[update_downgrades_bool]="${conf_a[bool_Downgrades]}"
[[ ! "${conf_a[bool_notifyMe]}" = "" ]]      && conf_a[notify_1enable_bool]="${conf_a[bool_notifyMe]}"
[[ ! "${conf_a[bool_updateFlatpak]}" = "" ]] && conf_a[flatpak_1enable_bool]="${conf_a[bool_updateFlatpak]}"
[[ ! "${conf_a[bool_updateKeys]}" = "" ]]    && conf_a[update_keys_bool]="${conf_a[bool_updateKeys]}"
[[ ! "${conf_a[str_ignorePackages]}" = "" ]] && conf_a[main_ignorepkgs_str]="${conf_a[str_ignorePackages]}"
[[ ! "${conf_a[str_log_d]}" = "" ]]          && conf_a[main_logdir_str]="${conf_a[str_log_d]}"
[[ ! "${conf_a[str_mirrorCountry]}" = "" ]]  && conf_a[main_country_str]="${conf_a[str_mirrorCountry]}"
[[ ! "${conf_a[str_testSite]}" = "" ]]       && conf_a[main_testsite_str]="${conf_a[str_testSite]}"

DEFAULTIFS=$IFS; IFS=$' '
for i in $(sort <<< "$conf_legacy"); do
	unset conf_a[$i]
done; IFS=$DEFAULTIFS


log_d="${conf_a[main_logdir_str]}"; log_f="${log_d}/auto-update.log"


#---Main---


#Start Sub-processes
if [ "$1" = "backnotify" ]; then backgroundnotify; exit 0; fi
if [ "$1" = "userlogon" ]; then userlogon; exit 0; fi

#Init log dir, check for other running instances, start notifier
mkdir -p "${conf_a[main_logdir_str]}"; if [ ! -d "${conf_a[main_logdir_str]}" ]; then conf_a[main_logdir_str]="/var/log/xs"; fi
mkdir -p "${conf_a[main_logdir_str]}"; if [ ! -d "${conf_a[main_logdir_str]}" ]; then
    echo "Critical error: could not create log directory"; sleep 10; exit; fi
if [ ! -f "$log_f" ]; then echo "init">$log_f; fi
if pidof -o %PPID -x "`basename "$0"`">/dev/null; then exit 0; fi #Only 1 main instance allowed
exportconf
if [ $# -eq 0 ]; then echo "`date` - XS-Update $vsndsp starting..." |tee $log_f; "$0" "XS"& exit 0; fi #Run in background

#Wait up to 5 minutes for network
trouble "Waiting for network..."
waiting=1;waited=0; while [ $waiting = 1 ]; do
    ping -c 1 "${conf_a[main_testsite_str]}" >/dev/null && waiting=0
    if [ $waiting = 1 ]; then
        if [ $waited -ge 60 ]; then exit; fi
        sleep 5; waited=$(($waited+1))
    fi
done; unset waiting; unset waited


sleep 8 # In case connection just established

#wait up to 5 minutes for running instances of pacman/apacman/pikaur
trouble "Waiting for pacman/apacman/pikaur..."
waiting=1;waited=0; while [ $waiting = 1 ]; do
    isRunning=0; pgrep pacman >/dev/null && isRunning=1
    pgrep apacman >/dev/null && isRunning=1; pgrep pikaur >/dev/null && isRunning=1
    [[ $isRunning = 1 ]] || waiting=0
    if [ $waiting = 1 ]; then
        if [ $waited -ge 60 ]; then exit; fi
        sleep 5; waited=$(($waited+1))
    fi
done;  unset waiting; unset waited; unset isRunning

#remove .lck file (pacman is not running at this point)
if [ -f /var/lib/pacman/db.lck ]; then rm -f /var/lib/pacman/db.lck; fi

#init main script and background notifications
trouble "Init vars and notifier..."
pacmirArgs="--geoip"
[[ "${conf_a[main_country_str]}" = "" ]] || pacmirArgs="-c ${conf_a[main_country_str]}"
[[ "${conf_a[main_ignorepkgs_str]}" = "" ]] || pacignore="--ignore ${conf_a[main_ignorepkgs_str]}"
[[ "${conf_a[update_downgrades_bool]}" = "$ctrue" ]] && pacdown="u"
[[ "${conf_a[aur_devel_bool]}" = "$ctrue" ]] && devel="--devel"
getsessions; i=0; while [ $i -lt ${#s_usr[@]} ]; do
if [ -d "${s_home[$i]}/.cache" ]; then
    mkdir -p "${s_home[$i]}/.cache/xs"; echo "tmp" > "${s_home[$i]}/.cache/xs/logonnotify"
    chown -R ${s_usr[$i]} "${s_home[$i]}/.cache/xs"; fi; i=$(($i+1)); done
"$0" "backnotify"& bkntfypid=$!

#Check for, download, and install main updates
pacclean
trouble "Updating Mirrors..."
pacman-mirrors $pacmirArgs 2>&1 |sed 's/\x1B\[[0-9;]\+[A-Za-z]//g' |tr -cd '\11\12\15\40-\176' |tee -a $log_f

trouble "Updating key packages..."
pacman -S --needed --noconfirm archlinux-keyring manjaro-keyring manjaro-system 2>&1 |tee -a $log_f

if [[ "${conf_a[update_keys_bool]}" = "$ctrue" ]]; then
    trouble "Refreshing keys..."; (pacman-key --refresh-keys; sync;)  2>&1 |tee -a $log_f; fi

trouble "Updating packages from main repos..."
pacman -Syyu$pacdown --needed --noconfirm $pacignore 2>&1 |tee -a $log_f


#Select supported/configured AUR Helper(s)
use_apacman=1; use_pikaur=1
if echo "${conf_a[aur_1helper_str]}" | grep "none" >/dev/null; then conf_a[aur_1helper_str]="none"; use_apacman=0; use_pikaur=0; fi
echo "${conf_a[aur_1helper_str]}" | grep 'all\|auto\|pikaur' >/dev/null || use_pikaur=0
echo "${conf_a[aur_1helper_str]}" | grep 'all\|auto\|apacman' >/dev/null || use_apacman=0

if [ "$use_pikaur" = "1" ]; then if ! type pikaur >/dev/null 2>&1; then
    use_pikaur=0
    if echo "${conf_a[aur_1helper_str]}" | grep 'pikaur' >/dev/null; then
        trouble "Warning: AURHelper: pikaur specified but not found..."
    fi
fi; fi

if [ "$use_apacman" = "1" ]; then if ! type apacman >/dev/null 2>&1; then
    use_apacman=0
    if echo "${conf_a[aur_1helper_str]}" | grep 'apacman' >/dev/null; then
        trouble "Warning: AURHelper: apacman specified but not found..."
    fi
fi; fi

if echo "${conf_a[aur_1helper_str]}" | grep 'auto' >/dev/null; then
    if [ "$use_pikaur" = "1" ]; then conf_a[aur_1helper_str]="auto"; use_apacman=0; fi; fi

#Update AUR packages

if [[ "$use_pikaur" = "1" ]]; then
    if [[ ! "${#flag_a}" = "0" ]]; then
        trouble "Updating AUR packages with custom flags [pikaur]..."
        for i in ${!flag_a[*]}; do
            pacman -Q $(echo "$i" | tr ',' ' ') && \
                pikaur -S --needed --noconfirm --noprogressbar --mflags=${flag_a[$i]} $(echo "$i" | tr ',' ' ') 2>&1 |tee -a $log_f
        done
    fi
    trouble "Updating normal AUR packages [pikaur]..."
    pikaur -Sau$pacdown $devel --needed --noconfirm --noprogressbar $pacignore 2>&1 |tee -a $log_f
fi

if [[ "$use_apacman" = "1" ]]; then
    # Workaround apacman script crash ( https://github.com/lectrode/xs-update-manjaro/issues/2 )
    dummystty="/tmp/xs-dummy/stty"
    mkdir `dirname $dummystty`
    echo '#!/bin/sh' >$dummystty
    echo "echo 15" >>$dummystty
    chmod +x $dummystty
    export PATH=`dirname $dummystty`:$PATH

    trouble "Updating AUR packages [apacman]..."
    apacman -Su$pacdown --auronly --needed --noconfirm $pacignore 2>&1 |\
        sed 's/\x1B\[[0-9;]\+[A-Za-z]//g' |tr -cd '\11\12\15\40-\176' |grep -v -F "%" |tee -a $log_f
    if [ -d "`dirname $dummystty`" ]; then rm -rf "`dirname $dummystty`"; fi
fi

#Remove orphan packages, cleanup
if [[ "${conf_a[cln_1enable_bool]}" = "$ctrue" ]]; then if [[ "${conf_a[cln_orphan_bool]}" = "$ctrue" ]]; then
    if [[ ! "$(pacman -Qtdq)" = "" ]]; then
        trouble "Removing orphan packages..."
        pacman -Rnsc $(pacman -Qtdq) --noconfirm  2>&1 |tee -a $log_f
    fi
fi; fi
pacclean

#Update Flatpak
if [[ "${conf_a[flatpak_1enable_bool]}" = "$ctrue" ]]; then if type flatpak >/dev/null 2>&1; then
    trouble "Updating flatpak..."
    flatpak update -y  2>&1 |tee -a $log_f
fi; fi

#Finish
trouble "Update completed, final notifications and cleanup..."
kill $bkntfypid
msg="System update finished"; grep "Total Installed Size:" $log_f >/dev/null && msg="$msg \nPackages successfully updated"
grep "new signatures:" $log_f >/dev/null && msg="$msg \nSecurity signatures updated"
grep "Total Removed Size:" $log_f >/dev/null && msg="$msg \nObsolete packages removed"
if [ "${conf_a[notify_errors_bool]}" = "$ctrue" ]; then grep "error: failed " $log_f >/dev/null && msg="$msg \nSome packages encountered errors"; fi
if [ ! "$msg" = "System update finished" ]; then msg="$msg \nDetails: $log_f"; fi
if [ "$msg" = "System update finished" ]; then msg="System up-to-date, no changes made"; fi
normcrit=norm; grep "upgrading " $log_f |grep -v "tor-browser"|grep -E "linux[0-9]{2,3}" >/dev/null && normcrit=crit
[[ "$normcrit" = "norm" ]] && finalmsg_normal; [[ "$normcrit" = "crit" ]] && finalmsg_critical
trouble "XS-done"; sleep 2; disown -a; sleep 2; systemctl stop xs-autoupdate.service >/dev/null 2>&1; exit 0

