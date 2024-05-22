find ./certora/conf -name '*.conf' -exec echo "running on" {} \; -exec certoraRun {} --server production \;
