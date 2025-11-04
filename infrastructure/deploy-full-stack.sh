#!/bin/bash
# deploy-full-stack.sh - Deploy Svelte frontend and Go backend

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Full Stack Deployment (Svelte + Go) ===${NC}\n"

# Check arguments
if [ $# -lt 3 ]; then
    echo -e "${RED}Usage: ./deploy-full-stack.sh <STACK_NAME> <FRONTEND_DIR> <BACKEND_DIR> [KEY_FILE]${NC}"
    echo ""
    echo "Arguments:"
    echo "  STACK_NAME    - CloudFormation stack name"
    echo "  FRONTEND_DIR  - Path to Svelte project directory"
    echo "  BACKEND_DIR   - Path to Go backend directory"
    echo "  KEY_FILE      - (Optional) SSH key for EC2 access"
    echo ""
    echo "Example:"
    echo "  ./deploy-full-stack.sh my-webapp ./frontend ./backend ~/.ssh/my-key.pem"
    exit 1
fi

STACK_NAME=$1
FRONTEND_DIR=$2
BACKEND_DIR=$3
KEY_FILE=${4:-""}

# Verify directories exist
if [ ! -d "$FRONTEND_DIR" ]; then
    echo -e "${RED}Error: Frontend directory not found: $FRONTEND_DIR${NC}"
    exit 1
fi

if [ ! -d "$BACKEND_DIR" ]; then
    echo -e "${RED}Error: Backend directory not found: $BACKEND_DIR${NC}"
    exit 1
fi

echo -e "${BLUE}Getting stack outputs...${NC}"
# Get stack outputs
OUTPUTS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs' --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Could not get stack outputs. Is the stack deployed?${NC}"
    exit 1
fi

# Extract values
STATIC_BUCKET=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="StaticAssetsBucket") | .OutputValue')
CLOUDFRONT_ID=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="CloudFrontDistributionId") | .OutputValue')
CLOUDFRONT_URL=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="CloudFrontURL") | .OutputValue')
BACKEND_IP=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="BackendInstancePublicIP") | .OutputValue')
ALB_ENDPOINT=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="ALBEndpoint") | .OutputValue')

echo -e "${GREEN}✓ Stack outputs retrieved${NC}"
echo "  Static Bucket: $STATIC_BUCKET"
echo "  CloudFront ID: $CLOUDFRONT_ID"
echo "  CloudFront URL: $CLOUDFRONT_URL"
echo "  Backend IP: $BACKEND_IP"
echo "  ALB Endpoint: $ALB_ENDPOINT"
echo ""

# ==========================================
# Deploy Frontend (Svelte)
# ==========================================
echo -e "${GREEN}Step 1: Building Svelte frontend...${NC}"

cd $FRONTEND_DIR

# Check if package.json exists
if [ ! -f "package.json" ]; then
    echo -e "${RED}Error: package.json not found in frontend directory${NC}"
    exit 1
fi

# Create/update .env file with API endpoint
cat > .env << EOF
VITE_API_URL=https://${CLOUDFRONT_URL}/api
VITE_ENVIRONMENT=production
EOF

echo -e "${YELLOW}Installing dependencies...${NC}"
npm install

echo -e "${YELLOW}Building production bundle...${NC}"
npm run build

if [ ! -d "dist" ] && [ ! -d "build" ]; then
    echo -e "${RED}Error: Build directory (dist or build) not found${NC}"
    exit 1
fi

# Determine build directory
BUILD_DIR="dist"
if [ -d "build" ]; then
    BUILD_DIR="build"
fi

echo -e "${GREEN}✓ Frontend built successfully${NC}"

echo -e "${GREEN}Step 2: Deploying frontend to S3...${NC}"

# Sync to S3
aws s3 sync $BUILD_DIR s3://$STATIC_BUCKET/ --delete \
    --cache-control "public, max-age=31536000, immutable" \
    --exclude "*.html" \
    --exclude "*.json"

# Upload HTML files with shorter cache
aws s3 sync $BUILD_DIR s3://$STATIC_BUCKET/ \
    --cache-control "public, max-age=0, must-revalidate" \
    --exclude "*" \
    --include "*.html" \
    --include "*.json"

echo -e "${GREEN}✓ Frontend deployed to S3${NC}"

echo -e "${GREEN}Step 3: Invalidating CloudFront cache...${NC}"
INVALIDATION_ID=$(aws cloudfront create-invalidation \
    --distribution-id $CLOUDFRONT_ID \
    --paths "/*" \
    --query 'Invalidation.Id' \
    --output text)

echo -e "${GREEN}✓ CloudFront invalidation created: $INVALIDATION_ID${NC}"

cd - > /dev/null

# ==========================================
# Deploy Backend (Go)
# ==========================================
echo -e "${GREEN}Step 4: Building Go backend...${NC}"

cd $BACKEND_DIR

# Check if main.go exists
if [ ! -f "main.go" ] && [ ! -f "cmd/main.go" ] && [ ! -f "cmd/server/main.go" ]; then
    echo -e "${RED}Error: main.go not found in backend directory${NC}"
    exit 1
fi

echo -e "${YELLOW}Compiling Go binary for Linux...${NC}"

# Build for Linux
GOOS=linux GOARCH=amd64 go build -o backend -ldflags="-s -w" .

if [ ! -f "backend" ]; then
    echo -e "${RED}Error: Backend binary not created${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Backend compiled successfully${NC}"
echo "  Binary size: $(du -h backend | cut -f1)"

cd - > /dev/null

# ==========================================
# Deploy to EC2
# ==========================================
if [ -n "$KEY_FILE" ]; then
    echo -e "${GREEN}Step 5: Deploying backend to EC2...${NC}"
    
    if [ ! -f "$KEY_FILE" ]; then
        echo -e "${RED}Error: Key file not found: $KEY_FILE${NC}"
        exit 1
    fi
    
    # Fix key permissions
    chmod 400 "$KEY_FILE"
    
    EC2_USER="ec2-user"
    REMOTE_DIR="/opt/webapp"
    
    echo -e "${YELLOW}Testing SSH connection...${NC}"
    ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "$EC2_USER@$BACKEND_IP" "echo 'Connection successful'" || {
        echo -e "${RED}Failed to connect to EC2 instance${NC}"
        exit 1
    }
    
    echo -e "${YELLOW}Uploading backend binary...${NC}"
    scp -i "$KEY_FILE" "$BACKEND_DIR/backend" "$EC2_USER@$BACKEND_IP:$REMOTE_DIR/"
    
    echo -e "${YELLOW}Setting permissions and restarting service...${NC}"
    ssh -i "$KEY_FILE" "$EC2_USER@$BACKEND_IP" << 'ENDSSH'
    sudo chmod +x /opt/webapp/backend
    sudo systemctl daemon-reload
    sudo systemctl restart backend
    sudo systemctl enable backend
    
    # Wait a moment for service to start
    sleep 3
    
    # Check service status
    sudo systemctl status backend --no-pager || true
    
    # Test health endpoint
    echo ""
    echo "Testing health endpoint..."
    curl -f http://localhost:8080/health || echo "Health check failed"
ENDSSH
    
    echo -e "${GREEN}✓ Backend deployed and running${NC}"
else
    echo -e "${YELLOW}Step 5: Skipping EC2 deployment (no key file provided)${NC}"
    echo -e "${YELLOW}Backend binary available at: $BACKEND_DIR/backend${NC}"
    echo -e "${YELLOW}To deploy manually:${NC}"
    echo -e "  scp -i YOUR_KEY backend ec2-user@$BACKEND_IP:/opt/webapp/"
    echo -e "  ssh -i YOUR_KEY ec2-user@$BACKEND_IP 'sudo systemctl restart backend'"
fi

# ==========================================
# Summary
# ==========================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Deployment Complete!                         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Frontend:${NC}"
echo -e "  🌐 URL: ${GREEN}$CLOUDFRONT_URL${NC}"
echo -e "  📦 S3 Bucket: $STATIC_BUCKET"
echo -e "  🔄 CloudFront Invalidation: $INVALIDATION_ID"
echo ""
echo -e "${BLUE}Backend:${NC}"
echo -e "  🖥️  EC2 Instance: $BACKEND_IP"
echo -e "  ⚖️  Load Balancer: http://$ALB_ENDPOINT"
echo -e "  🔌 API Endpoint: $CLOUDFRONT_URL/api"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
if [ -n "$KEY_FILE" ]; then
    echo -e "  View logs:    ${YELLOW}ssh -i $KEY_FILE ec2-user@$BACKEND_IP 'sudo journalctl -u backend -f'${NC}"
    echo -e "  Restart API:  ${YELLOW}ssh -i $KEY_FILE ec2-user@$BACKEND_IP 'sudo systemctl restart backend'${NC}"
    echo -e "  Check status: ${YELLOW}ssh -i $KEY_FILE ec2-user@$BACKEND_IP 'sudo systemctl status backend'${NC}"
fi
echo -e "  Check CloudFront: ${YELLOW}aws cloudfront get-invalidation --distribution-id $CLOUDFRONT_ID --id $INVALIDATION_ID${NC}"
echo ""
echo -e "${GREEN}🎉 Your Svelte + Go application is live!${NC}"
