.PHONY: help install uninstall test release version update

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  install    Interactively configure and install server-guardian (run with sudo)"
	@echo "  uninstall  Remove server-guardian from the scheduler"
	@echo "  test       Run the test suite"
	@echo "  version    Show the installed server-guardian version"
	@echo "  update     Update to the latest GitHub release (run with sudo, on production)"
	@echo "  release    Tag a new release (suggests a semver bump, pushes the tag)"

install:
	@bash install.sh

uninstall:
	@if [ -d /run/systemd/system ]; then \
	  sudo systemctl stop guardian.timer 2>/dev/null || true; \
	  sudo systemctl disable guardian.timer 2>/dev/null || true; \
	  sudo rm -f /etc/systemd/system/guardian.service \
	             /etc/systemd/system/guardian.timer; \
	  sudo systemctl daemon-reload; \
	else \
	  sudo crontab -l 2>/dev/null | grep -v "guardian.sh" | sudo crontab -; \
	fi
	@echo "Uninstalled."

test:
	@bash tests/guardian.test.sh

version:
	@if [ -f VERSION ]; then \
	  echo "server-guardian v$$(cat VERSION)"; \
	else \
	  echo "server-guardian (unknown version, no VERSION file found)"; \
	fi

update:
	@bash update.sh

release:
	@bash release.sh
