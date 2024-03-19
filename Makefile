PATH := ~/.solc-select/artifacts/solc-0.8.14:~/.solc-select/artifacts/solc-0.5.12:$(PATH)
all         :; FOUNDRY_OPTIMIZER=true FOUNDRY_OPTIMIZER_RUNS=200 forge build --use solc:0.8.14
clean       :; forge clean
certora-hub :; PATH=${PATH} certoraRun certora/D3MHub.conf$(if $(rule), --rule $(rule),)
deploy      :; ./deploy.sh config="$(config)"
deploy-core :; ./deploy-core.sh
