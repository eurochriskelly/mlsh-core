#!/bin/bash
#
here=$(pwd)
repo=$(basename $here)
there=$(dirname $0)

mkdir -p bin/ scripts/ src/

touch bin/index.js

export MLSH_CORE_REPONAME=$repo
tpl=node_modules/mlsh-core/package.json.plugin-template
envsubst < $tpl > package.json
