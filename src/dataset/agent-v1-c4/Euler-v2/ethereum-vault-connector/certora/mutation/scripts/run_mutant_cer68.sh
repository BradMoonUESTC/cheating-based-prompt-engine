#!/bin/sh
# Run mutation testing for CER-68 from root directory
certoraMutate --prover_conf certora/conf/CER-2-Operator/CER-68-Operator-authorization.conf  --mutation_conf certora/mutation/conf/MutateCER68.conf --server production --msg "manual mutant for CER-68"