# Makefile
.PHONY: test
RPC_URL=http://localhost:8545

# Load .env automatically (if using bash)
include .env

clean:
	forge clean

deploy:
	forge script ./script/Deployer.s.sol --broadcast --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY)

build:
	forge build

test:
	forge test

fmt:
	forge fmt

all: clean deploy build test
