.PHONY: up down reset ps logs

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
