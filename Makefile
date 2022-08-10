all    		 :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.8.14 build
clean  		 :; dapp clean
test   		 :; ./test.sh match="$(match)" optimizer=1
test-dev   	 :; ./test.sh match="$(match)" optimizer=0
test-forge 	 :; ./test-forge.sh match="$(match)" block="$(block)" match-test="$(match-test)" match-contract="$(match-contract)"
certora-hub  :; PATH=~/.solc-select/artifacts:${PATH} certoraRun --solc_map D3MHub=solc-0.8.14,Vat=solc-0.5.12,DaiJoin=solc-0.5.12,Dai=solc-0.5.12,PlanMock=solc-0.8.14,PoolMock=solc-0.8.14 --rule_sanity basic src/D3MHub.sol certora/mocks/Vat.sol certora/mocks/DaiJoin.sol certora/mocks/Dai.sol certora/mocks/PlanMock.sol certora/mocks/PoolMock.sol --link D3MHub:vat=Vat D3MHub:daiJoin=DaiJoin DaiJoin:vat=Vat DaiJoin:dai=Dai PlanMock:dai=Dai PoolMock:hub=D3MHub PoolMock:vat=Vat PoolMock:dai=Dai --verify D3MHub:certora/D3MHub.spec $(if $(rule),--rule $(rule),) --multi_assert_check --short_output
