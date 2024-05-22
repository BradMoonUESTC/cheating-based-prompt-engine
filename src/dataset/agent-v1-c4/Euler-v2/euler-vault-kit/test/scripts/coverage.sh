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
lcov --rc branch_coverage=1 \
    --output-file forge-pruned-lcov.info \
		--ignore-errors inconsistent \
    --remove lcov.info $EXCLUDE

if [ "$CI" != "true" ]; then
    genhtml --rc branch_coverage=1 \
		--ignore-errors category \
		--ignore-errors inconsistent \
		--output-directory coverage forge-pruned-lcov.info \
        && open coverage/index.html
fi
