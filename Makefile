SHELL = /bin/bash -o pipefail
export PATH := $(shell go env GOPATH)/bin:$(PATH)

ROOT_DIR=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
SRC_DIR=$(ROOT_DIR)/src
MIGRATIONS_DIR=$(ROOT_DIR)/src/migrations
CONFIG_FILE=$(ROOT_DIR)/config.yml
CONFIG_TEST_FILE=$(ROOT_DIR)/config_test.yml
BIN=$(ROOT_DIR)/bin/bot
REVISION=$(shell git describe --tags 2>/dev/null || git log --format="v0.0-%h" -n 1 || echo "v0.0-unknown")

build: deps fmt packr_install
	@echo "==> Building"
	@cd $(SRC_DIR) && packr2 && CGO_ENABLED=0 go build -o $(BIN) -ldflags "-X common.build=${REVISION}" .
	@cd $(SRC_DIR) && packr2 clean
	@echo $(BIN)

run: migrate
	@echo "==> Running"
	@${BIN} --config $(CONFIG_FILE) run

test: clean config_test deps fmt migrate_test
	@echo "==> Running tests"
	@cd $(SRC_DIR) && go test ./... -v -cpu 2 -cover -race

ci: clean migrate_test
	@echo "==> Running tests"
	@go test ./... -v -cpu 2 -race -coverpkg=./... -coverprofile=$(ROOT_DIR)/coverage.out | tee $(ROOT_DIR)/test-report.txt
	@go get -v -u github.com/axw/gocov/gocov
	@gocov convert $(ROOT_DIR)/coverage.out | gocov report
	@go mod tidy

test_reports:
	@go get -v -u github.com/jstemmer/go-junit-report
	@cat $(ROOT_DIR)/test-report.txt | /go/bin/go-junit-report > $(ROOT_DIR)/test-report.xml || true

config_test:
ifeq (,$(wildcard ./config_test.yml))
	@cp config_test.yml.dist config_test.yml
endif

fmt:
	@echo "==> Running gofmt"
	@gofmt -l -s -w $(SRC_DIR)

deps:
	@echo "==> Installing dependencies"
	@go mod tidy

migrate: build
	${BIN} --config $(CONFIG_FILE) migrate

migrate_test: config_test build
	@${BIN} --config $(CONFIG_TEST_FILE) migrate

migrate_down: build
	@${BIN} --config $(CONFIG_FILE) migrate -v down

migration: transport_tool_install
	@transport-core-tool migration -d $(MIGRATIONS_DIR)

.PHONY: clean
clean: packr_install
	@cd $(SRC_DIR) && packr2 clean
	@rm -rf coverage.out test-report.{txt,xml}
	@cp -fru config_test.yml.dist config_test.yml

transport_tool_install:
ifeq (, $(shell command -v transport-core-tool 2> /dev/null))
	@echo "==> Installing migration generator..."
	@go get -u github.com/retailcrm/mg-transport-core/cmd/transport-core-tool
endif

packr_install:
ifeq (, $(shell command -v packr2 2> /dev/null))
	@go get github.com/gobuffalo/packr/v2/packr2@v2.7.1
endif
