FOUNDRY_PROFILE=coverage forge coverage --report lcov \
&& lcov --rc branch_coverage=1 \
    --output-file forge-pruned-lcov.info \
    --remove lcov.info "test/" && \
genhtml forge-pruned-lcov.info -o coverage-report --branch-coverage