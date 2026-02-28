# Frappe Docker Commands

# Start stack and enter interactive mode in one command
dev: up shell

# Start the devcontainer stack
up:
    docker compose -f .devcontainer/docker-compose.yml up -d

# Stop the devcontainer stack
stop:
    docker compose -f .devcontainer/docker-compose.yml stop

# Stop and remove the devcontainer stack
down:
    docker compose -f .devcontainer/docker-compose.yml down

# Enter the frappe container in interactive mode
shell:
    docker compose -f .devcontainer/docker-compose.yml exec --user frappe --workdir /workspace/development/frappe-bench frappe bash

# View logs from all devcontainer services
logs:
    docker compose -f .devcontainer/docker-compose.yml logs -f

# Restart the devcontainer stack
restart: down up

# Clean up all development containers and volumes (careful!)
clean:
    docker compose -f .devcontainer/docker-compose.yml down -v --remove-orphans

# Start production environment
prod-up:
    docker compose up -d

# Stop production environment
prod-down:
    docker compose down

