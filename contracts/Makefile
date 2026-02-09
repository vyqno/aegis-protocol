# ================================================================
#  AEGIS Protocol - Comprehensive Test Suite Makefile
#  Usage: make <target>
# ================================================================

# Config
FORGE := forge
ANVIL := anvil
ANVIL_PORT := 8545
ANVIL_RPC := http://127.0.0.1:$(ANVIL_PORT)

# ================================================================
#  QUICK COMMANDS
# ================================================================

.PHONY: all test clean

## Run all tests (unit + fuzz + integration + invariant + e2e + deployment)
all: test

## Run the full test suite with verbose output
test:
	$(FORGE) test -vvv

## Run tests with gas reporting
test-gas:
	$(FORGE) test -vvv --gas-report

## Clean build artifacts
clean:
	$(FORGE) clean

# ================================================================
#  INDIVIDUAL TEST SUITES
# ================================================================

## Unit tests only
test-unit:
	$(FORGE) test --match-path "test/unit/*" -vvv

## Fuzz tests only
test-fuzz:
	$(FORGE) test --match-path "test/fuzz/*" -vvv

## Integration tests only
test-integration:
	$(FORGE) test --match-path "test/integration/*" -vvv

## Invariant tests only
test-invariant:
	$(FORGE) test --match-path "test/invariant/*" -vvv

## Deployment verification tests
test-deployment:
	$(FORGE) test --match-path "test/deployment/*" -vvv

## End-to-end tests (CRE workflow sim + production lifecycle + Anvil)
test-e2e:
	$(FORGE) test --match-path "test/e2e/*" -vvv

# ================================================================
#  CYFRIN DEVOPS TESTS
# ================================================================

## Deployment verification with Cyfrin DevOps
test-devops:
	$(FORGE) test --match-contract DeploymentVerificationTest -vvv

## Gas profiling tests
test-gas-profile:
	$(FORGE) test --match-test "test_gasProfile" -vvv

## Bytecode size verification
test-bytecode:
	$(FORGE) test --match-test "test_bytecodeSize" -vvv

# ================================================================
#  CRE WORKFLOW TESTS
# ================================================================

## CRE workflow simulation tests
test-cre:
	$(FORGE) test --match-contract CREWorkflowSimulationTest -vvv

## Full CRE lifecycle test
test-cre-lifecycle:
	$(FORGE) test --match-test "test_fullCRELifecycle" -vvv

## Production lifecycle simulation
test-production:
	$(FORGE) test --match-contract ProductionLifecycleTest -vvv

# ================================================================
#  ANVIL DEPLOYMENT + TEST
# ================================================================

## Start Anvil, deploy, and run tests against live node
anvil-test:
	@echo "Starting Anvil..."
	@$(ANVIL) --port $(ANVIL_PORT) --block-time 1 &
	@sleep 2
	@echo "Deploying to Anvil..."
	$(FORGE) script script/DeployAnvil.s.sol --rpc-url $(ANVIL_RPC) --broadcast || true
	@echo "Running Anvil integration tests..."
	$(FORGE) test --match-contract AnvilDeployAndTestTest -vvv
	@echo "Stopping Anvil..."
	@pkill -f "anvil --port $(ANVIL_PORT)" || true

## Deploy to Anvil only (no tests)
anvil-deploy:
	@echo "Starting Anvil..."
	@$(ANVIL) --port $(ANVIL_PORT) &
	@sleep 2
	$(FORGE) script script/DeployAnvil.s.sol --rpc-url $(ANVIL_RPC) --broadcast
	@echo "Anvil running at $(ANVIL_RPC)"
	@echo "Press Ctrl+C to stop"

# ================================================================
#  COVERAGE & ANALYSIS
# ================================================================

## Run coverage report
coverage:
	$(FORGE) coverage

## Run coverage with lcov output
coverage-lcov:
	$(FORGE) coverage --report lcov

## Run Slither static analysis (requires slither-analyzer)
slither:
	slither . --config-file slither.config.json || slither .

# ================================================================
#  CI/CD TARGETS
# ================================================================

## Full CI pipeline: build + test + coverage
ci: clean
	$(FORGE) build
	$(FORGE) test -vvv
	$(FORGE) test --match-path "test/e2e/*" -vvv
	$(FORGE) test --match-path "test/deployment/*" -vvv
	@echo "CI pipeline passed!"

## Pre-deployment checks
pre-deploy: test-deployment test-e2e test-bytecode test-gas-profile
	@echo "All pre-deployment checks passed!"

# ================================================================
#  HELP
# ================================================================

## Show available targets
help:
	@echo "AEGIS Protocol Test Suite"
	@echo "========================"
	@echo ""
	@echo "Quick:"
	@echo "  make test              - Run all tests"
	@echo "  make test-gas          - Run tests with gas report"
	@echo ""
	@echo "By category:"
	@echo "  make test-unit         - Unit tests"
	@echo "  make test-fuzz         - Fuzz tests"
	@echo "  make test-integration  - Integration tests"
	@echo "  make test-invariant    - Invariant tests"
	@echo "  make test-deployment   - Deployment verification"
	@echo "  make test-e2e          - End-to-end tests"
	@echo ""
	@echo "Specialized:"
	@echo "  make test-devops       - Cyfrin DevOps checks"
	@echo "  make test-cre          - CRE workflow simulation"
	@echo "  make test-production   - Production lifecycle sim"
	@echo "  make test-gas-profile  - Gas profiling"
	@echo "  make test-bytecode     - Bytecode size check"
	@echo ""
	@echo "Anvil:"
	@echo "  make anvil-test        - Full Anvil deploy + test"
	@echo "  make anvil-deploy      - Deploy to local Anvil"
	@echo ""
	@echo "CI/CD:"
	@echo "  make ci                - Full CI pipeline"
	@echo "  make pre-deploy        - Pre-deployment checks"
	@echo "  make coverage          - Coverage report"
