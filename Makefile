.PHONY: install uninstall test

install:
	@sudo bash install.sh

uninstall:
	@sudo systemctl stop guardian.timer 2>/dev/null || true
	@sudo systemctl disable guardian.timer 2>/dev/null || true
	@sudo rm -f /etc/systemd/system/guardian.service \
	            /etc/systemd/system/guardian.timer
	@sudo systemctl daemon-reload
	@echo "Uninstalled."

test:
	@bash tests/guardian.test.sh
