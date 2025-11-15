.PHONY: help deploy start stop restart logs test clean update

help:
	@echo "DoH Server for Xbox Network - Available Commands:"
	@echo ""
	@echo "  make deploy    - Deploy DoH server (first-time setup)"
	@echo "  make start     - Start all services"
	@echo "  make stop      - Stop all services"
	@echo "  make restart   - Restart all services"
	@echo "  make logs      - View logs (follow mode)"
	@echo "  make test      - Test DNS resolution"
	@echo "  make update    - Update Docker images"
	@echo "  make clean     - Stop and remove all containers"
	@echo "  make status    - Show service status"
	@echo ""

deploy:
	@echo "Deploying DoH server..."
	@chmod +x deploy.sh
	@sudo ./deploy.sh

start:
	@echo "Starting services..."
	@docker-compose up -d
	@echo "Services started. Use 'make logs' to view output."

stop:
	@echo "Stopping services..."
	@docker-compose down

restart:
	@echo "Restarting services..."
	@docker-compose restart
	@echo "Services restarted."

logs:
	@docker-compose logs -f

test:
	@echo "Testing DNS resolution..."
	@chmod +x test-dns.sh
	@./test-dns.sh localhost

status:
	@docker-compose ps

update:
	@echo "Updating Docker images..."
	@docker-compose pull
	@docker-compose up -d
	@echo "Update complete."

clean:
	@echo "Cleaning up..."
	@docker-compose down -v
	@echo "All containers and volumes removed."

.DEFAULT_GOAL := help

