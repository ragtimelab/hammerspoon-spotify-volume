.PHONY: test build verify package install verify-install rollback uninstall

test:
	./scripts/test

build:
	./scripts/build

verify: test build
	./Tests/Lua/install_test.zsh

package:
	./scripts/package

install:
	./scripts/install

verify-install:
	./scripts/verify-install

rollback:
	./scripts/rollback

uninstall:
	./scripts/uninstall
