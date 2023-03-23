#!/usr/bin/env bash
{
## This is an adapter which forwards the active Jenkins job to `homerdo`.
##
## This script is part of a 3-step lifecycle:
##
## 1. REQUEST: The dispatch-user receives a Jenkins job. It records the current request.
## 2. SETUP: The user `runner-N` should have a re-usable/baseline environment with
##    common tools and caches. Initialize these.
## 3. EXEC:  The user `runner-N` should fetch and execute the specific code-under-test.
##
## Each step is described below with examples.

#####################################################################
## Internal Environment
##
## BKNIX_JOBS:   This folder (containing the *.job scripts)
## REQUEST:      File with the serialized request
## BKIT:         Path for the active buildkit instance

TTL_TOOLS=60     ## During setup, refresh 'civi-download-tools' (if >1 hour old)
TTL_BLDTYPE=180  ## During setup, warmup 'bldtype' (if >3 hours since last)

#####################################################################
## Main
function main() {
  case "$1" in
    request)     do_request ; ;;
    pick-image)  REQUEST="$2" ; load_request "$REQUEST" ; do_image ; ;;
    setup)       REQUEST="$2" ; load_request "$REQUEST" ; do_setup ; ;;
    exec)        REQUEST="$2" ; load_request "$REQUEST" ; do_exec ; ;;
    run)         REQUEST="$2" ; load_request "$REQUEST" ; do_setup ; do_exec ; ;;
  esac
}

#####################################################################
## TASK: New Request
## USER: (anyone)
## EXAMPLE: `homerdo-task.sh request > /tmp/request-1234.txt`
##
## Generate a request message. This will be relayed to other subtasks.

function do_request() {
  echo >&2 "[$USER] Generate request"
  env | known_variables | switch_home
}

#####################################################################
## TASK: Pick image
## USER: (anyone)
## EXAMPLE: `cd $IMGDIR && flock . homerdo-task.sh pick-image /tmp/request-1234.txt`
##
## Choose which image-file to use as homer's $HOME.
## NOTE: For concurrent invocations, run this with `flock`.

function do_image() {
  echo >&2 "[$USER] Pick image"
  
  local n=0
  local img="bknix-$BKPROF-$n.img"
  local is_new
  local status
  while true; do
    #echo >&2 "check $n: $img"
    if [ ! -e "$img" ]; then
      is_new=1
      break
    fi
    #echo >&2 "CALL: homerdo status -i \"$img\""
    status=$(homerdo status -i "$img")
    if [ "$status" == "avail" ]; then
      is_new=
      break
    fi
    n=$((1 + $n))
    img="bknix-$BKPROF-$n.img"
  done
  
  if [[ -n $is_new ]]; then
    homerdo create -i "$img"
  fi
  realpath "$img"
}

#####################################################################
## TASK: Setup Base Layer
## USER: "homer"
## HOME FILE MODE: "Base"
## EXAMPLE: `homerdo-task.sh setup /tmp/request-1234.txt > /tmp/my-log.txt`
##
## Use this to download common tools or warm-up common caches. Anything you
## do during "setup" will may be re-used in future calls.
##
## Do not use this for the heavy-lifting of job execution. You probably
## should NOT retrieve any unapproved/PR content.

function do_setup() {
  echo >&2 "[$USER] Run setup for request $REQUEST"

  git config --global user.email "$USER@example.com"
  git config --global user.name "$USER"
  mkdir -p "$HOME/.cache-flags"

  if [ ! -d "$BKIT" ]; then
    git clone https://github.com/civicrm/civicrm-buildkit "$BKIT"
  fi

  if is_stale "$BKIT/.ttl-tools" "$TTL_TOOLS" ; then
    (cd "$BKIT" && git pull)
    # (cd "$BKIT" && nix-shell -A "$BKPROF" --run './bin/civi-download-tools')
    (cd "$BKIT" && nix-shell -A "$BKPROF" --run './bin/civi-download-tools && civibuild cache-warmup')
    touch "$BKIT/.ttl-tools"
  fi

  ## Every few hours, the "setup" does a trial run to re-warm caches.
  ## (It might preferrable to get composer+npm to use a general HTTP cache, but this will work for now.)
  safe_delete "$BKIT/build/warmup" "$BKIT/build/warmup.sh"
  if [[ -d "$BKIT/app/config/$BLDTYPE" && "$BLDTYPE" =~ ^(drupal|drupal8|drupal9|backdrop|wp|standalone)-(empty|clean|demo)$ ]]; then
    local flag_file="$BKIT/.ttl-$BLDTYPE"
    if is_stale "$flag_file" "$TTL_BLDTYPE" ; then
      safe_delete "$BKIT/build/warmup" "$BKIT/build/warmup.sh"
      (cd "$BKIT" && nix-shell -A "$BKPROF" --run "civibuild download warmup --type $BLDTYPE")
      safe_delete "$BKIT/build/warmup" "$BKIT/build/warmup.sh"
      touch "$flag_file"
    fi
  fi

  # echo "EXEC: Start pre-setup shell. Press Ctrl-D to finish pre-run shell." && bash
}

#####################################################################
## TASK: Execute job
## USER: "homer"
## HOME FILE MODE: "Temp"
## EXAMPLE: `homerdo-task.sh exec /tmp/request-1234.txt > /tmp/my-log.txt`
##
## Use this to do the heavy-lifting of job execution. You might create
## new sites, run PHPUnit, etc.
##
## You will be allowed to write files anywhere in "$HOME", but they will be
## reset when the job finishes.

function do_exec() {
  echo >&2 "[$USER] Run exec for request $REQUEST"

  # echo "EXEC: Start pre-run shell. Press Ctrl-D to finish pre-run shell." && bash

  use_workspace
  mkdir build
  cd build
  pwd
  cat "$REQUEST" > env-requested.txt
  cat "$REQUEST" | well_formed_variables | known_variables > env-effective.txt

  cd "$BKIT"
  cat ".loco/worker-n.yml" | grep -v CIVI_TEST_MODE > ".loco/loco.yml"
  local cmd=$(printf "run-bknix-job --loaded %q" "$BKPROF")
  nix-shell -A "$BKPROF" --run "$cmd"

  # echo "EXEC: Start post-run shell. Press Ctrl-D to finish post-run shell." && nix-shell -A "$BKPROF"
}

#####################################################################
## Utilities

## Ensure that the WORKSPACE folder is setup.
function use_workspace() {
  echo >&2 "Use workspace ($WORKSPACE)"
  if [ -z "$WORKSPACE" ]; then
    echo >&2 "Error: Missing WORKSPACE"
    exit 1
  fi
  if [ ! -d "$WORKSPACE" ]; then
    mkdir -p "$WORKSPACE"
  fi
  cd "$WORKSPACE"
}

## Load data from a request file.
## usage: load_request <REQ_FILE>
function load_request() {
  #eval $( cat "$1" | well_formed_variables | new_variables | escape_variables )
  eval $( cat "$1" | well_formed_variables | known_variables | escape_variables )

  case "$BKPROF" in
    old|min|dfl|max|edge)
      BKIT="$HOME/buildkit"
      ;;
    *)
      echo >&2 "Unrecognized BKPROF=[$BKPROF]"
      exit 3
      ;;
  esac
}

function well_formed_variables() {
  grep -v '^#' | grep '^[a-zA-Z0-9_]\+='
}

## Filter the variables. Only return new/undefined values.
##
## STDIN: List of KEY=VALUE pairs (unescaped values)
## STDOUT: List of KEY=VALUE pairs (unescaped values)
function new_variables() {
  while IFS= read -r line; do
    var=$(echo "$line" | cut -d= -f1)
    if [[ -z "${!var}" ]]; then
      echo "$line"
    fi
  done

}

## Filter the variable. Only return well-known (pre-declared) variables.
##
## STDIN: List of KEY=VALUE pairs (unescaped values)
## STDOUT: List of KEY=VALUE pairs (unescaped values)
function known_variables() {
  env_list=" "$(echo $( cat "$BKNIX_JOBS/env.txt" | grep '^[a-zA-Z0-9_]\+$' ; echo ))" "
  #echo >&2 "$JOBDIR/env.txt: $env_list"
  while IFS= read -r line; do
    var=$(echo "$line" | cut -d= -f1)
    if [[ "$env_list" =~ " $var " ]]; then
      echo "$line"
    fi
  done
}

## Filter any variables that refer to `~dispatcher` and plug in our own user.
function switch_home() {
  local old_home="$HOME"
  local new_home="/home/homer"
  sed "s;$old_home;$new_home;"
}


## Encode the variables in a way that's suitable for "eval"
##
## STDIN: List of KEY=VALUE pairs (unescaped values)
## STDOUT: List of KEY=VALUE pairs (escaped values; suited for "eval")
function escape_variables() {
  local my_exports=()

  while IFS= read -r line; do
    var=$(echo "$line" | cut -d= -f1)
    val=$(echo "$line" | cut -d= -f2-)
    printf "$var=%q\n" "$val"
    my_exports+=( "$var" )
  done

  if [ ${#my_exports[@]} -gt 0 ]; then
    echo "export ${my_exports[@]}"
  fi
}

## Check if it's time for an update
## usage: is_stale <MARKER> <MINUTES>
function is_stale () {
  local file_path="$1"
  local max_age_minutes="$2"

  if [[ ! -f "$file_path" ]]; then
    # File does not exist, so it's expired
    return 0
  fi

  local file_age_seconds=$(( $(date +%s) - $(stat -c %Y "$file_path") ))
  local max_age_seconds=$(( max_age_minutes * 60 ))

  if [[ $file_age_seconds -gt $max_age_seconds ]]; then
    # File is older than the specified max age
    return 0
  else
    # File is not older than the specified max age
    return 1
  fi
}

function safe_delete() {
  for FILE in "$@" ; do
    if [[ -f "$FILE" ]]; then
      rm "$FILE"
    elif [[ -d "$FILE" ]]; then
      rm -rf "$FILE"
    fi
  done
}

function absdirname() {
  pushd $(dirname $0) >> /dev/null
    pwd
  popd >> /dev/null
}

#####################################################################
## Go

export BKNIX_JOBS=$(absdirname "$0")
main "$@"
exit $?
}
