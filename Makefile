.PHONY: verify setup doctor runtime-install build-pip smoke live-smoke install-plugin clean

verify:
	python3 scripts/verify-plugin.py

setup:
	./scripts/setup.sh

doctor:
	./scripts/doctor.sh

runtime-install:
	./scripts/ocu-runtime.sh install

build-pip:
	./scripts/build-computer-use-pip.sh

smoke:
	OPEN_COMPUTER_USE_AUTO_INSTALL=0 python3 scripts/mcp-smoke.py

live-smoke: smoke
	OPEN_COMPUTER_USE_AUTO_INSTALL=0 ./scripts/ocu-runtime.sh call list_apps

install-plugin:
	./scripts/install-local-plugin.sh

clean:
	rm -rf dist __pycache__ scripts/__pycache__ scripts/lib/__pycache__
