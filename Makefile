# This makefile leverages automatic documentation. Running `make` will generate a list
# of the most commonly used targets. `make help` will generate a more complete list.
#
# When adding a target, prefix the doc string with two pound signs to add it to the common
# list or two pounds and VERBOSE to demote it to the `make help` list. Prefix it with two pounds
# and INTERNAL to exclude from all help, or just don't add a doc string.
#
# Based on https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html

.DEFAULT_GOAL := help
SHELL=/bin/bash -o pipefail

# Supports:
#   make install /usr/local/bin
#   make install
INSTALLPATH ?= $(if $(word 2,$(MAKECMDGOALS)),$(word 2,$(MAKECMDGOALS)),$(HOME)/bin)

ifneq (,$(filter install,$(MAKECMDGOALS)))
ifneq ($(word 2,$(MAKECMDGOALS)),)
.PHONY: $(word 2,$(MAKECMDGOALS))
$(word 2,$(MAKECMDGOALS)):
	@:
endif
endif

.PHONY: help
help: ##META Display all make targets
	@printf "\33[32m"
	@echo "All documented make targets. Use 'make' to see only the most commonly used targets."
	@printf "\033[0m\n"

	@grep -E '^%?[a-zA-Z0-9/_-]+:.*?##(VERBOSE)? .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?##(VERBOSE)? "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# Compile both executables in bin
.PHONY: install
install: ## Build and install executables (default: ~/bin)
	@mkdir -p "$(INSTALLPATH)"
	dart compile exe bin/replace.dart -o "$(INSTALLPATH)/replace"
	dart compile exe bin/pm.dart -o "$(INSTALLPATH)/pm"