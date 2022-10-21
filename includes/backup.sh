#!/bin/bash

## Simple shortcut to just list the backups without promts and such
listBackups(){
echo -e "${BWhite}Backup Listing Tool${Color_Off}"
clear -x && echo "pulling all restore points.."
list_backups=$(cli -c 'app kubernetes list_backups' | grep -v system-update | sort -t '_' -Vr -k2,7 | tr -d " \t\r"  | awk -F '|'  '{print $2}' | nl | column -t)
[[ -z "$list_backups" ]] && echo -e "${IRed}No restore points available${Color_Off}" && exit || echo "Detected Backups:" && echo "$list_backups"
}
export -f listBackups

## Lists backups, except system-created backups, and promts which one to delete
deleteBackup(){
echo -e "${BWhite}Backup Deletion Tool${Color_Off}"
clear -x && echo "pulling all restore points.."
list_delete_backups=$(cli -c 'app kubernetes list_backups' | grep -v system-update | sort -t '_' -Vr -k2,7 | tr -d " \t\r"  | awk -F '|'  '{print $2}' | nl | column -t)
clear -x
# shellcheck disable=SC2015
[[ -z "$list_delete_backups" ]] && echo -e "${IRed}No restore points available${Color_Off}" && exit || { title; echo -e "Choose a restore point to delete\nThese may be out of order if they are not TrueTool backups" ;  }
# shellcheck disable=SC2015
echo "$list_delete_backups" && read -rt 600 -p "Please type a number: " selection && restore_point=$(echo "$list_delete_backups" | grep ^"$selection " | awk '{print $2}')
[[ -z "$selection" ]] && echo "${IRed}Your selection cannot be empty${Color_Off}" && exit #Check for valid selection. If none, kill script
[[ -z "$restore_point" ]] && echo "Invalid Selection: $selection, was not an option" && exit #Check for valid selection. If none, kill script
echo -e "\nWARNING:\nYou CANNOT go back after deleting your restore point" || { echo "${IRed}FAILED${Color_Off}"; exit; }
# shellcheck disable=SC2015
echo -e "\n\nYou have chosen:\n$restore_point\n\nWould you like to continue?"  && echo -e "1  Yes\n2  No" && read -rt 120 -p "Please type a number: " yesno || { echo "${IRed}FAILED${Color_Off}"; exit; }
if [[ $yesno == "1" ]]; then
    echo -e "\nDeleting $restore_point" && cli -c 'app kubernetes delete_backup backup_name=''"'"$restore_point"'"' &>/dev/null && echo -e "${IGreen}Sucessfully deleted${Color_Off}" || echo -e "${IRed}Deletion FAILED${Color_Off}"
elif [[ $yesno == "2" ]]; then
    echo "You've chosen NO, killing script."
else
    echo -e "${IRed}Invalid Selection${Color_Off}"
fi
}
export -f deleteBackup

## Creates backups and deletes backups if a "backups to keep"-count is exceeded.
# backups-to-keep takes only heavyscript and truetool created backups into account, as other backups aren't guaranteed to be sorted correctly
backup(){
echo -e "${BWhite}Backup Tool${Color_Off}"
echo -e "\nNumber of backups was set to $number_of_backups"
date=$(date '+%Y_%m_%d_%H_%M_%S')
[[ "$verbose" == "true" ]] && cli -c 'app kubernetes backup_chart_releases backup_name=''"'TrueTool_"$date"'"'
[[ -z "$verbose" ]] && echo -e "\nNew Backup Name:" && cli -c 'app kubernetes backup_chart_releases backup_name=''"'TrueTool_"$date"'"' | tail -n 1
mapfile -t list_create_backups < <(cli -c 'app kubernetes list_backups' | grep 'HeavyScript\|TrueTool_' | sort -t '_' -Vr -k2,7 | awk -F '|'  '{print $2}'| tr -d " \t\r")
# shellcheck disable=SC2309
if [[  ${#list_create_backups[@]}  -gt  "number_of_backups" ]]; then
    echo -e "\nDeleting the oldest backup(s) for exceeding limit:"
    overflow=$(( ${#list_create_backups[@]} - "$number_of_backups" ))
    mapfile -t list_overflow < <(cli -c 'app kubernetes list_backups' | grep "TrueTool_"  | sort -t '_' -V -k2,7 | awk -F '|'  '{print $2}'| tr -d " \t\r" | head -n "$overflow")
    for i in "${list_overflow[@]}"
    do
        cli -c 'app kubernetes delete_backup backup_name=''"'"$i"'"' &> /dev/null || echo "${IRed}FAILED${Color_Off} to delete $i"
        echo "$i"
    done
fi
}
export -f backup

## Lists available backup and prompts the users to select a backup to restore
restore(){
echo -e "${BWhite}Backup Restoration Tool${Color_Off}"
clear -x && echo "pulling restore points.."
list_restore_backups=$(cli -c 'app kubernetes list_backups' | grep "TrueTool_" | sort -t '_' -Vr -k2,7 | tr -d " \t\r"  | awk -F '|'  '{print $2}' | nl | column -t)
clear -x
# shellcheck disable=SC2015
[[ -z "$list_restore_backups" ]] && echo "No TrueTool restore points available" && exit || { title; echo "Choose a restore point" ;  }
echo "$list_restore_backups" && read -rt 600 -p "Please type a number: " selection && restore_point=$(echo "$list_restore_backups" | grep ^"$selection " | awk '{print $2}')
[[ -z "$selection" ]] && echo "Your selection cannot be empty" && exit #Check for valid selection. If none, kill script
[[ -z "$restore_point" ]] && echo "Invalid Selection: $selection, was not an option" && exit #Check for valid selection. If none, kill script
echo -e "\nWARNING:\nThis is NOT guranteed to work\nThis is ONLY supposed to be used as a LAST RESORT\nConsider rolling back your applications instead if possible" || { echo "${IRed}FAILED${Color_Off}"; exit; }
# shellcheck disable=SC2015
echo -e "\n\nYou have chosen:\n$restore_point\n\nWould you like to continue?"  && echo -e "1  Yes\n2  No" && read -rt 120 -p "Please type a number: " yesno || { echo "${IRed}FAILED${Color_Off}"; exit; }
if [[ $yesno == "1" ]]; then
    echo -e "\nStarting Restore, this will take a ${BWhite}LONG${Color_Off} time."
    zfs set mountpoint=legacy "$(zfs list -t filesystem -r "$(cli -c 'app kubernetes config' | grep -E "pool\s\|" | awk -F '|' '{print $3}' | tr -d " \t\n\r")" -o name -H | grep "volumes/pvc")" && echo "Fixing PVC mountpoints..." || echo "Fixing PVC mountpoints Failed... Continuing with restore..."
    cli -c 'app kubernetes restore_backup backup_name=''"'"$restore_point"'"' || echo "Restore ${IRed}FAILED${Color_Off}"
elif [[ $yesno == "2" ]]; then
    echo "You've chosen NO, killing script. Good luck."
else
    echo -e "${IRed}Invalid Selection${Color_Off}"
fi
}
export -f restore
