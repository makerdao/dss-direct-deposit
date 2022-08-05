all    		 :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 dapp --use solc:0.8.14 build
clean  		 :; dapp clean
test   		 :; ./test.sh match="$(match)" optimizer=1
test-dev   	 :; ./test.sh match="$(match)" optimizer=0
test-forge 	 :; ./test-forge.sh match="$(match)" block="$(block)" match-test="$(match-test)" match-contract="$(match-contract)"
certora-hub  :; certoraRun --solc ~/.solc-select/artifacts/solc-0.8.14 --rule_sanity basic src/D3MHub.sol certora/mocks/VatMock.sol certora/mocks/DaiJoinMock.sol certora/mocks/DaiMock.sol certora/mocks/PlanMock.sol certora/mocks/PoolMock.sol --link D3MHub:vat=VatMock D3MHub:daiJoin=DaiJoinMock DaiJoinMock:vat=VatMock DaiJoinMock:dai=DaiMock PlanMock:dai=DaiMock PoolMock:hub=D3MHub PoolMock:vat=VatMock PoolMock:dai=DaiMock --verify D3MHub:certora/D3mHub.spec $(if $(rule),--rule $(rule),) --multi_assert_check --short_output
