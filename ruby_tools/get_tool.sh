#! /usr/bin/env bash

function die {
    echo "$@"
    exit 1
}

function main {

    local TOOL_TYPE="$1"
    local TOOL_VERSION="$2"


    mkdir -p "$TOOL_TYPE-$TOOL_VERSION"

    (
	cd "$TOOL_TYPE-$TOOL_VERSION"

	gem fetch "$TOOL_TYPE" --version "$TOOL_VERSION"

	if [[ $? -ne 0 ]]; then
	  die "FAILED: gem fetch $TOOL_TYPE --version $TOOL_VERSION"
	fi

	gem install "$TOOL_TYPE" --version "$TOOL_VERSION" --install-dir "$PWD"
	
	find . -maxdepth 1 -mindepth 1 -type d ! -name cache | xargs rm -rf
	find . -maxdepth 1 -mindepth 1 -type f -name '*.gem'| xargs rm -rf
	mv cache/*.gem .
	rm -rf cache
    )
    
}

main "$@"
