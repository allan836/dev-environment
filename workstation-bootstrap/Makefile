.PHONY: setup up down verify logs

setup:
	./setup.sh

up:
	docker compose up -d

down:
	docker compose down

verify:
	./scripts/verify.sh

logs:
	docker compose logs -f
