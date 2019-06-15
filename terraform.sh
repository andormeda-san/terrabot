#!/usr/bin/env bash

## variables
# common
SETTINGS_FILE="/xxxterrabot/menu.json"
PRJ=$(cat ${SETTINGS_FILE} | jq -r '.actions[0].options[].value' | grep -v all-project)
AWS_DIR="/xxx"
GCP_DIR="/xxx/terraform"
LOG_DIR="/xxx/log"
ALL_LOG_FILE="${LOG_DIR}/all_$(date +%Y%m%d%H%M).log"
# slack
SLACK_URL="https://hooks.slack.com/xxx/xxx/xxx/xxx"
SLACK_POST_TPL="/xxx/terrabot/result_tpl.json"
POST_RESULT=$(cat ${SLACK_POST_TPL})
POST_RESULT_JSON=${LOG_DIR}/result_$(date +%Y%m%d%H%M).json
# gcp
GSUTIL="gs://xxxxx/"
GCS="https://xxx/xxx/"

## logging
function outputchenge(){
# exec 1> >(awk '{print strftime("[%Y-%m-%d %H:%M:%S]"),$0 } { fflush() } ' >>${1})
# exec 2> >(awk '{print strftime("[%Y-%m-%d %H:%M:%S]"),$0 } { fflush() } ' >>${1})
exec >>${1}
exec 2>&1
}

outputchenge ${ALL_LOG_FILE}

## check
# gcloud
echo "[Info] Start checking for the gsutil command."
if  ! type gsutil; then
    echo "[Error] gsutil not found"
    exit 1
fi
echo "[Info] End checking for the gsutil command."

# check jq
echo "[Info] Start checking for the jq command."
if  ! type jq; then
    echo "[Error] jq not found"
    exit 1
fi
echo "[Info] End checking for the jq command."

# check arg
echo "[Info] Start checking for the number of args."
if [ ${#} -ne 2 ]; then
    echo "[Error] ${#} is invalid number of args."
    echo "[Error] specified args is ${@}."
    exit 1
fi
echo "[Info] specified args is ${@}."
echo "[Info] End checking for the number of args."


function terraformplan () {
    LOG_FILE="${1}_$(date +%Y%m%d%H%M).log"
    LOG_FILE_FULL_PATH="${LOG_DIR}/${LOG_FILE}"
    outputchenge ${LOG_FILE_FULL_PATH}
    if [ ${2} = "aws" ]; then
        echo "[Info] Provider is ${2}."
        cd ${AWS_DIR}/${1}/terraform
    elif [ ${2} = "gcp" ]; then
        echo "[Info] Provider is ${2}."
        cd ${GCP_DIR}/${1}
    else
        echo "[error] ${2} is invalid provider."
    fi
    echo "[Info] Start 'git pull'."
    git pull
    echo "[Info] Start 'terraform init --upgrade'."
    terraform init --upgrade | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g"
    echo "[Info] Start 'terraform version'."
    terraform version | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g"
    for i in $(seq 1 5)
        do
        echo "[Info] Start 'terraform plan. take ${i}'."
        terraform plan | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g"
        if [ "$(cat ${LOG_FILE_FULL_PATH} | grep "No changes")" -o "$(cat ${LOG_FILE_FULL_PATH} | grep "Plan")" ]; then
            break
        fi
        done
}

function slackpost () {
    if [ "$(cat ${LOG_FILE_FULL_PATH} | grep "No changes")" ]; then
            COLOR="good"
            TITLE=${1}
            TEXT=$(cat ${LOG_FILE_FULL_PATH} | grep "No changes")
    elif [ "$(cat ${LOG_FILE_FULL_PATH} | grep "Plan")" ]; then
            COLOR="warning"
            TITLE=${1}
            TEXT=$(cat ${LOG_FILE_FULL_PATH} | grep "Plan")
    elif [ "$(cat ${LOG_FILE_FULL_PATH} | grep "Error")" ]; then
            COLOR="danger"
            TITLE=${1}
            TEXT=$(cat ${LOG_FILE_FULL_PATH} | grep "Error")
    else
            COLOR=""
            TITLE=${1}
            TEXT=""
    fi
    POST_RESULT=$(echo ${POST_RESULT}| jq '.attachments |= .+[
    {
        "color": "'"${COLOR}"'",
        "title": "'"${1}"'",
        "text": "'"${TEXT}"'",
        "title_link": "'"${GCS}${LOG_FILE}"'"
    }
]')
    gsutil -h "Content-Type:text/plain" cp ${LOG_FILE_FULL_PATH} ${GSUTIL} && rm -f ${LOG_FILE_FULL_PATH} 
}
# main

echo "1: ${1} 2: ${2}"

if [ "${2}" = "all" ]; then
    while read line
    do
        terraformplan ${line}
        slackpost ${line}
    done <<PRJ
    $PRJ
PRJ
else
    terraformplan ${1} ${2}
    slackpost ${1} ${2}
fi


echo ${POST_RESULT} >${POST_RESULT_JSON}
curl -X POST ${SLACK_URL} -d @${POST_RESULT_JSON}
