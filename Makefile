.PHONY: dev-server dev-web build-server build-web start-web docker-up docker-down test-server test-server-e2e test-web test-e2e install-hooks

dev-server:
	cd server && go run ./cmd/server

dev-web:
	cd apps/web && npm run dev

build-server:
	cd server && go build -o ../bin/aceso-server ./cmd/server

build-web:
	cd apps/web && npm run build

start-web:
	cd apps/web && npm run start

docker-up:
	docker compose -f docker/docker-compose.yml up --build

docker-down:
	docker compose -f docker/docker-compose.yml down

test-server:
	cd server && go test ./...

test-server-e2e:
	cd server && go test -tags=e2e ./e2e/...

test-web:
	cd apps/web && npm test

test-e2e:
	cd apps/web && npm run test:e2e

install-hooks:
	pre-commit install
	pre-commit install --hook-type commit-msg
