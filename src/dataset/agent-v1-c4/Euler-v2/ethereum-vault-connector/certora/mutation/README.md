# Mutation Testing
This directory contains files relevant to mutation testing using certoraMutate.
More information about certoraMutate and Gambit can be found
[here](https://docs.certora.com/en/latest/docs/gambit/mutation-verifier.html).
At the time of writing Gambit is used exclusively to test rules against manually
crafted bug injections.

# Directory structure
- conf: configuration files for mutation testing 
- mutants: solidity contracts modified to include bug injections 
- scripts: run scripts to do testing


# Instructions
If you've installed `certora-cli` then `certoraMutate` is already installed as
well.  Simply run `cd` into the root directory for this repository and run the
script related to the bug of interest in the scripts directory.

# Bug Descriptions
Here we describe each mutant. The changes can easily be found within the mutated file by
searching for a comment with the word "Mutate"

### Mutant CER-68
This mutant is based on a prior audit report which found a bug in EthereumVaultConnector.sol
The change is as follows:
```
diff --git a/src/EthereumVaultConnector.sol b/src/EthereumVaultConnector.sol
index 1c0a327..4316f49 100644
--- a/src/EthereumVaultConnector.sol
+++ b/src/EthereumVaultConnector.sol
@@ -310,7 +310,7 @@ contract EthereumVaultConnector is Events, Errors, TransientStorage, IEVC {
         address owner = haveCommonOwnerInternal(account, msgSender) ? msgSender : getAccountOwnerInternal(account);
 
         // if it's an operator calling, it can only act for itself and must not be able to change other operators status
-        if (owner != msgSender && operator != msgSender) {
+        if (owner != msg.sender && operator != msg.sender && address(this) != msg.sender) {
             revert EVC_NotAuthorized();
         }
 
```