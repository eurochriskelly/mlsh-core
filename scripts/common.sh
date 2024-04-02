#!/bin/bash

II() { echo "II $(date) $@"; }
# script that only echos if $MLSH_DEBUG is set
DD() { if [ -n "$MLSH_DEBUG" ]; then echo "DD $(date) $@"; fi; }
EE() { echo "EE $(date) $@"; }
WW() { echo "WW $(date) $@"; }
LL() { echo "$(date) $@" >> /tmp/mlsh.log; }

fetch() {
  local endpoint=$1
  shift
  local rest=($@)
  local URL="${ML_PROTOCOL}://${ML_HOST}:${ML_PORT}${endpoint}"
  # TODO generate based on environment
  local curlOpts=(
    --insecure
    -u "$ML_USER:$ML_PASS"
    -k --digest -s
    "${rest[@]}"
  )
  LL "curl ${curlOpts[@]} $URL"
  curl "${curlOpts[@]}" "$URL"
}

doEval() {
  DD "Evaluating script [$1] against database [$2] with vars [$3]"
  local script=
  local base=$MLSH_TOP_DIR/scripts/eval/${1}
  # Check if it exists in the scripts/eval directory
  if [[ -f "${base}.xqy" || -f "${base}.sjs" || -f "${base}.js" ]]; then
    if [ -f "${base}.xqy" ]; then
      script=$MLSH_TOP_DIR/scripts/eval/${1}.xqy
    else
      if [ -f "${base}.sjs" ]; then
        script=$MLSH_TOP_DIR/scripts/eval/${1}.sjs
      else
        script=$MLSH_TOP_DIR/scripts/eval/${1}.js
      fi
    fi
  fi

  # Check if it exists locally
  if [ -z "$script" ]; then
    # check if $1 with either xqy OR js extension exists in current directory
    if [[ -f "${1}.xqy" || -f "${1}.sjs" || -f "${1}.js" ]]
    then if [ -f "${1}.xqy" ]
         then script=${1}.xqy
         else if [ -f "${1}.sjs" ]
              then script=${1}.sjs
              else script=${1}.js
              fi
         fi
     fi
  fi

  if [ -z "$script" ]; then
    WW "Script [$1] not found in $MLSH_TOP_DIR/scripts/eval or current directory."
    ls $MLSH_TOP_DIR/scripts/eval
    return 1
  else
    DD "Found matching script [$script]"
  fi

  if [ "$script" == "1" ]; then
    DD "No script [$1] found in $MLSH_TOP_DIR/scripts/eval or ."
    return 1
  fi
  LL Script : $script
  local format=javascript
  local extension="${script##*.}"
  if [ "$extension" == "xqy" ];then format=xquery;fi
  local opts=(
    -X POST
    --data-urlencode ${format}@${script}
    --data database="$2"
  )
  if [ -n "$3" ];then opts=( "${opts[@]}" --data-urlencode vars=$3 );fi
  local response=$(fetch "/v1/eval" "${opts[@]}")
  # if response is > 50 lines, reduce to 50 lines and add a line "See /tmp/mlsh-eval.out for full response"
  while read -r line; do
    local c2=$(echo $line|cut -c1-2|sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case "$c2" in
      # Ignore log messages
      "II") ;;
      "EE") ;;
      "WW") ;;
      "DD") ;;
      "--") ;;
      "") ;;
      *)
        # Ignore lines starting with "Content-Type" or "X-Primitive"
        if [[ "$line" != "Content-Type"* && "$line" != "X-Primitive"* ]]; then
          echo $line
        fi
    esac
  done <<< "$response"
}

# Useful function for converting
# strings in the format A:B,C:D to {"A":"B","C":"D"}
# without the need for escaping everything
toJson() {
  local input=$1
  IFS=',' read -ra arr <<< "$input"
  local json="{"
  for i in "${arr[@]}";do
    IFS=':' read -ra subarr <<< "$i"
    json+="\"${subarr[0]}\":\"${subarr[1]}\","
  done
  json="${json%,}"}
  echo $json
}

to_json() {
  local input_str="$1"
  local first=true

  echo -n "{"

  IFS=',' read -ra pairs <<< "$input_str"
  for pair in "${pairs[@]}"; do
    IFS='=' read -ra kv <<< "$pair"
    key="${kv[0]}"
    value="${kv[1]}"

    if [ "$first" = true ]; then
      first=false
    else
      echo -n ","
    fi

    echo -n "\"$key\":\"$value\""
  done

  echo "}"
}

# Common functions
mle() {
  local fname=$1
  local params=$2
  if [ -n "$params" ];then
    params=$(toJson $params)
  fi
  local result=
  if [ -z "${params}" ];then
    result=$($MLSH_CMD eval -s "${fname}.xqy")
  else
    result=$($MLSH_CMD eval -s "${fname}.xqy" -p "${params}")
  fi
  if [ -n "$(echo $result | grep 'Internal Server Error')" ];then
    echo "$result"
    echo " ---------------------------------"
    echo "Error Exiting !"
    exit 1
  fi
  echo "$result"
}
