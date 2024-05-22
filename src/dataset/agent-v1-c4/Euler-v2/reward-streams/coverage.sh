#!/bin/bash

# generates lcov.info
forge coverage --report lcov --no-match-test testFork

if ! command -v lcov &>/dev/null; then
    echo "lcov is not installed. Installing..."
	# check if its macos or linux.
	if [ "$(uname)" == "Darwin" ]; then
		brew install lcov
	else
		sudo apt-get install lcov
	fi
fi

lcov --version

# forge does not instrument libraries https://github.com/foundry-rs/foundry/issues/4854
EXCLUDE="*test* *mock* *node_modules* $(grep -r 'library' contracts -l)"
lcov --rc lcov_branch_coverage=1 \
    --output-file forge-pruned-lcov.info \
    --remove lcov.info $EXCLUDE

if [ "$CI" != "true" ]; then
    genhtml --rc lcov_branch_coverage=1 \
		--ignore-errors category \
        --output-directory coverage forge-pruned-lcov.info \
        && open coverage/index.html
fi
