.PHONY: setup verify kv-load-images kv-up kv-init kv-clean-slate kv-clean-slate-remote kv-down kv-status kv-verify kv-logs

setup:
	./setup.sh

verify:
	./scripts/verify.sh

kv-load-images:
	./scripts/kv-backend.sh load-images

kv-up:
	./scripts/kv-backend.sh up

kv-init:
	./scripts/kv-backend.sh init

kv-clean-slate:
	./scripts/kv-clean-slate.sh

kv-clean-slate-remote:
	./scripts/kv-clean-slate.sh --remote

kv-down:
	./scripts/kv-backend.sh down

kv-status:
	./scripts/kv-backend.sh status

kv-verify:
	./scripts/kv-backend.sh verify

kv-logs:
	cd "$${KV_BACKEND_DIR:-$$HOME/workspace/repos/kv-backend}/preload-docker-compose" && docker compose logs -f
