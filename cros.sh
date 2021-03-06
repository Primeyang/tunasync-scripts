#!/bin/bash
set -e

USE_BITMAP_INDEX=${USE_BITMAP_INDEX:-"0"}
CONCURRENT_JOBS=${CONCURRENT_JOBS:-"1"}
MANIFEST_URL=$TUNASYNC_UPSTREAM_URL/chromiumos/manifest.git
MANIFEST_DIR=$TUNASYNC_WORKING_DIR/.manifest
MANIFEST_XML_REPOLIST=$(dirname $0)/helpers/manifest-xml-repolist.py
IGNORED_REPO=(
)

export GIT_TERMINAL_PROMPT=0

function contains() {
    for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
    return 1
}

function git_clone_or_pull {
    URL=$1
    DIRECTORY=$2
    BARE=$3
    if [[ -z $BARE ]]; then
        if [[ -d $DIRECTORY ]]; then
            git -C $DIRECTORY pull
        else
            git clone $URL $DIRECTORY
        fi
    else
        if [[ -d $DIRECTORY ]]; then
            git -C $DIRECTORY fetch --force --prune
        else
            git clone --bare $URL $DIRECTORY
        fi
    fi
}

function git_repack() {
	echo "Start writing bitmap index"
	while read repo; do
		cd $repo
		size=$(du -sk .|cut -f1)
		total_size=$(($total_size+1024*$size))
		objs=$(find objects -type f  | wc -l)
		if [[ "$objs" -gt 8 && "$size" -gt "100000" ]]; then
			git repack -a -b -d
		fi
	done < <(find $TUNASYNC_WORKING_DIR -not -path "$MANIFEST_DIR/.git/*" -type f -name HEAD -exec dirname '{}' ';')
}

git_clone_or_pull $MANIFEST_URL $MANIFEST_DIR

for repo in $($MANIFEST_XML_REPOLIST $MANIFEST_DIR/default.xml cros chromium); do
    contains $repo ${IGNORED_REPO[@]} && continue
    echo $TUNASYNC_UPSTREAM_URL/$repo
    if [[ -z ${DRY_RUN:-} ]]; then
        while true
        do
            running=$(jobs -r | wc -l)
            if [ "$running" -lt "$CONCURRENT_JOBS" ]
            then
                echo "start cloning $repo"
                git_clone_or_pull $TUNASYNC_UPSTREAM_URL/$repo $TUNASYNC_WORKING_DIR/$repo yes &
                break
            else
                wait -n
            fi
        done
    fi
done

wait # wait for all background jobs

total_size=0
if [[ -z ${DRY_RUN:-} && "$USE_BITMAP_INDEX" == "1" ]]; then
    git_repack
    echo "Total size is" $(numfmt --to=iec $total_size)
fi
