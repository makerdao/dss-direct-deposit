all    		 :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.8.14 build
clean  		 :; dapp clean
test   		 :; ./test.sh match="$(match)" optimizer=1
test-dev   	 :; ./test.sh match="$(match)" optimizer=0
test-forge 	 :; ./test-forge.sh match="$(match)" block="$(block)" match-test="$(match-test)" match-contract="$(match-contract)"
