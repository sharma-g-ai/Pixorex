.PHONY: up down reset ps logs migrate seed

up:     ## start the local stack
	docker compose up -d

down:   ## stop the stack, keep data
	docker compose down

reset:  ## stop the stack and delete all local data
	docker compose down -v

ps:     ## service health
	docker compose ps

logs:   ## follow logs (make logs s=keycloak)
	docker compose logs -f $(s)

migrate: ## apply database migrations (runs once on `up` too)
	docker compose run --rm migrate

seed:   ## load the synthetic demo data (local only)
	docker compose run --rm migrate python scripts/seed_synthetic.py
