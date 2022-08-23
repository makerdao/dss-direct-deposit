all    		 :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.8.14 build
clean  		 :; dapp clean
test   		 :; ./test.sh match="$(match)" optimizer=1
test-dev   	 :; ./test.sh match="$(match)" optimizer=0
test-forge 	 :; ./test-forge.sh match="$(match)" block="$(block)" match-test="$(match-test)" match-contract="$(match-contract)"
certora-hub  :; PATH=~/.solc-select/artifacts:${PATH} certoraRun --solc_map D3MHub=solc-0.8.14,Vat=solc-0.5.12,DaiJoin=solc-0.5.12,Dai=solc-0.5.12,End=solc-0.5.12,D3MTestPlan=solc-0.8.14,D3MTestPool=solc-0.8.14,D3MTestGem=solc-0.8.14 --rule_sanity basic src/D3MHub.sol certora/dss/Vat.sol certora/dss/DaiJoin.sol certora/dss/Dai.sol certora/dss/End.sol src/tests/stubs/D3MTestPlan.sol src/tests/stubs/D3MTestPool.sol src/tests/stubs/D3MTestGem.sol --link D3MHub:vat=Vat D3MHub:daiJoin=DaiJoin D3MHub:end=End DaiJoin:vat=Vat DaiJoin:dai=Dai End:vat=Vat D3MTestPlan:dai=Dai D3MTestPool:hub=D3MHub D3MTestPool:vat=Vat D3MTestPool:dai=Dai D3MTestPool:share=D3MTestGem --verify D3MHub:certora/D3MHub.spec --staging$(if $(short), --short_output,)$(if $(rule), --rule $(rule),)$(if $(multi), --multi_assert_check,)
