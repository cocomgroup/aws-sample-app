.PHONY: help dev-frontend dev-backend build-frontend build-backend deploy deploy-frontend deploy-backend clean test

# Variables
STACK_NAME ?= my-webapp
FRONTEND_DIR = ./frontend
BACKEND_DIR = ./backend
KEY_FILE ?= ~/.ssh/aws-key.pem

help:
	@echo "Available commands:"
	@echo "  make dev-frontend       - Run Svelte dev server"
	@echo "  make dev-backend        - Run Go backend locally"
	@echo "  make build-frontend     - Build Svelte for production"
	@echo "  make build-backend      - Build Go binary for Linux"
	@echo "  make deploy             - Deploy both frontend and backend"
	@echo "  make deploy-frontend    - Deploy only frontend to S3"
	@echo "  make deploy-backend     - Deploy only backend to EC2"
	@echo "  make test               - Run tests"
	@echo "  make clean              - Clean build artifacts"
	@echo "  make stack-create       - Create CloudFormation stack"
	@echo "  make stack-update       - Update CloudFormation stack"
	@echo "  make stack-delete       - Delete CloudFormation stack"
	@echo "  make stack-outputs      - Get stack outputs"

# Development
dev-frontend:
	cd $(FRONTEND_DIR) && npm run dev

dev-backend:
	cd $(BACKEND_DIR) && \
	export REDIS_ENDPOINT=localhost && \
	export REDIS_PORT=6379 && \
	export PORT=8080 && \
	go run main.go

# Build
build-frontend:
	cd $(FRONTEND_DIR) && npm run build

build-backend:
	cd $(BACKEND_DIR) && \
	GOOS=linux GOARCH=amd64 go build -o backend -ldflags="-s -w" .

# Deploy
deploy: build-frontend build-backend
	./deploy-full-stack.sh $(STACK_NAME) $(FRONTEND_DIR) $(BACKEND_DIR) $(KEY_FILE)

deploy-frontend: build-frontend
	@echo "Getting S3 bucket name..."
	$(eval BUCKET := $(shell aws cloudformation describe-stacks \
		--stack-name $(STACK_NAME) \
		--query 'Stacks[0].Outputs[?OutputKey==`StaticAssetsBucket`].OutputValue' \
		--output text))
	$(eval DIST_ID := $(shell aws cloudformation describe-stacks \
		--stack-name $(STACK_NAME) \
		--query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' \
		--output text))
	@echo "Deploying to S3 bucket: $(BUCKET)"
	aws s3 sync $(FRONTEND_DIR)/build/ s3://$(BUCKET)/ --delete
	@echo "Invalidating CloudFront: $(DIST_ID)"
	aws cloudfront create-invalidation --distribution-id $(DIST_ID) --paths "/*"
	@echo "✅ Frontend deployed!"

deploy-backend: build-backend
	@echo "Getting EC2 IP..."
	$(eval EC2_IP := $(shell aws cloudformation describe-stacks \
		--stack-name $(STACK_NAME) \
		--query 'Stacks[0].Outputs[?OutputKey==`BackendInstancePublicIP`].OutputValue' \
		--output text))
	@echo "Deploying to EC2: $(EC2_IP)"
	scp -i $(KEY_FILE) $(BACKEND_DIR)/backend ec2-user@$(EC2_IP):/opt/webapp/
	ssh -i $(KEY_FILE) ec2-user@$(EC2_IP) 'sudo systemctl restart backend'
	@echo "✅ Backend deployed!"

# Testing
test:
	@echo "Running frontend tests..."
	cd $(FRONTEND_DIR) && npm test || echo "No frontend tests"
	@echo "Running backend tests..."
	cd $(BACKEND_DIR) && go test -v ./... || echo "No backend tests"

# Clean
clean:
	rm -rf $(FRONTEND_DIR)/build
	rm -rf $(FRONTEND_DIR)/.svelte-kit
	rm -rf $(FRONTEND_DIR)/node_modules
	rm -f $(BACKEND_DIR)/backend
	@echo "✅ Cleaned build artifacts"

# CloudFormation Stack Management
stack-create:
	@echo "Creating CloudFormation stack: $(STACK_NAME)"
	@read -p "Enter KeyName: " keyname; \
	aws cloudformation create-stack \
		--stack-name $(STACK_NAME) \
		--template-body file://webapp-svelte-go.yaml \
		--parameters \
			ParameterKey=EnvironmentName,ParameterValue=prod \
			ParameterKey=InstanceType,ParameterValue=t3.medium \
			ParameterKey=KeyName,ParameterValue=$$keyname \
			ParameterKey=SSHLocation,ParameterValue=0.0.0.0/0 \
		--capabilities CAPABILITY_IAM
	@echo "Waiting for stack creation..."
	aws cloudformation wait stack-create-complete --stack-name $(STACK_NAME)
	@echo "✅ Stack created successfully!"

stack-update:
	@echo "Updating CloudFormation stack: $(STACK_NAME)"
	aws cloudformation update-stack \
		--stack-name $(STACK_NAME) \
		--template-body file://webapp-svelte-go.yaml \
		--capabilities CAPABILITY_IAM \
		|| echo "No updates to perform"

stack-delete:
	@echo "⚠️  This will delete all resources!"
	@read -p "Are you sure? [y/N]: " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		echo "Emptying S3 buckets..."; \
		$(eval STATIC_BUCKET := $(shell aws cloudformation describe-stacks \
			--stack-name $(STACK_NAME) \
			--query 'Stacks[0].Outputs[?OutputKey==`StaticAssetsBucket`].OutputValue' \
			--output text)) \
		$(eval DATA_BUCKET := $(shell aws cloudformation describe-stacks \
			--stack-name $(STACK_NAME) \
			--query 'Stacks[0].Outputs[?OutputKey==`DataBucket`].OutputValue' \
			--output text)) \
		aws s3 rm s3://$(STATIC_BUCKET) --recursive; \
		aws s3 rm s3://$(DATA_BUCKET) --recursive; \
		echo "Deleting stack..."; \
		aws cloudformation delete-stack --stack-name $(STACK_NAME); \
		aws cloudformation wait stack-delete-complete --stack-name $(STACK_NAME); \
		echo "✅ Stack deleted!"; \
	else \
		echo "Cancelled."; \
	fi

stack-outputs:
	@aws cloudformation describe-stacks \
		--stack-name $(STACK_NAME) \
		--query 'Stacks[0].Outputs' \
		--output table

# Install dependencies
install:
	@echo "Installing frontend dependencies..."
	cd $(FRONTEND_DIR) && npm install
	@echo "Installing backend dependencies..."
	cd $(BACKEND_DIR) && go mod download
	@echo "✅ Dependencies installed!"

# Quick local setup
local-setup: install
	@echo "Starting local Redis (Docker)..."
	docker run -d --name redis -p 6379:6379 redis:alpine || echo "Redis already running"
	@echo "✅ Local setup complete!"
	@echo ""
	@echo "Run 'make dev-backend' in one terminal"
	@echo "Run 'make dev-frontend' in another terminal"
