SHELL := /usr/bin/env bash

.PHONY: lint start stop status clean

lint:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "shellcheck is required for lint"; \
		exit 1; \
	fi
	shellcheck -x bin/lvm lib/*.sh start-mesh.sh setup-vm.sh launch-monitoring-vm.sh

start:
	./bin/lvm start

stop:
	./bin/lvm stop

status:
	./bin/lvm status

clean:
	./bin/lvm clean
