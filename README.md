# Svelte + Go AWS CloudFormation Project

Complete infrastructure and application templates for deploying a TypeScript/Svelte frontend with Go backend on AWS.

## 📁 Project Structure

```
project/
├── infrastructure/
│   ├── webapp-svelte-go.yaml        # Full CloudFormation template (Svelte + Go)
│   ├── webapp-basic.yaml            # Basic template (Node.js example)
│   ├── deploy-full-stack.sh         # Automated deployment script
│   └── README-basic.md              # Basic setup guide
│
├── backend-example/
│   ├── main.go                      # Complete Go API server
│   └── go.mod                       # Go dependencies
│
├── frontend-example/
│   ├── src/
│   │   └── lib/
│   │       └── api.ts               # TypeScript API client
│   ├── vite.config.ts               # Vite build configuration
│   ├── svelte.config.js             # SvelteKit configuration
│   ├── tsconfig.json                # TypeScript configuration
│   └── package.json                 # Frontend dependencies
│
├── .github/
│   └── workflows/
│       └── deploy.yml               # GitHub Actions CI/CD
│
├── Makefile                         # Development commands
└── SETUP_GUIDE.md                   # Complete setup documentation
```

## 🏗️ Architecture

### Infrastructure Components

1. **CloudFront + S3**
   - CloudFront CDN for global content delivery
   - S3 bucket for static Svelte assets
   - Automatic HTTPS with CloudFront

2. **Application Load Balancer + EC2**
   - ALB for load balancing and health checks
   - EC2 instance running Go backend
   - Auto-configured systemd service

3. **ElastiCache Redis**
   - In-memory caching layer
   - Private subnet deployment
   - Automatic failover support

4. **DynamoDB**
   - NoSQL database
   - Pay-per-request billing
   - Point-in-time recovery enabled
   - Global secondary indexes

5. **VPC Networking**
   - Public/private subnets across 2 AZs
   - Internet Gateway for public access
   - Security groups for network isolation

## 🚀 Quick Start

### Prerequisites
- AWS CLI configured
- Node.js 18+ and npm
- Go 1.21+
- EC2 Key Pair

### 1. Deploy Infrastructure

```bash
# Navigate to infrastructure directory
cd infrastructure

# Create the stack
aws cloudformation create-stack --stack-name my-webapp --template-body file://infrastructure/webapp-svelte-go.yaml --parameters ParameterKey=KeyName,ParameterValue=my-key ParameterKey=EnvironmentName,ParameterValue=dev ParameterKey=InstanceType,ParameterValue=t3.micro --capabilities CAPABILITY_IAM --region us-east-1

# Wait for completion (10-15 minutes)
aws cloudformation wait stack-create-complete --stack-name my-webapp
```

### 2. Set Up Your Projects

#### Frontend (Svelte):
```bash
# Create SvelteKit project
npm create svelte@latest frontend
cd frontend

# Copy configuration files
cp ../frontend-example/svelte.config.js .
cp ../frontend-example/vite.config.ts .
cp ../frontend-example/tsconfig.json .

# Copy API client
mkdir -p src/lib
cp ../frontend-example/src/lib/api.ts src/lib/

# Install dependencies
npm install
npm install -D @sveltejs/adapter-static
```

#### Backend (Go):
```bash
# Create backend directory
mkdir backend
cd backend

# Copy example files
cp ../backend-example/main.go .
cp ../backend-example/go.mod .

# Customize go.mod with your module name
# Install dependencies
go mod tidy
go mod download
go run main.go
```

### 3. Deploy Application

```bash
# Make deploy script executable
chmod +x infrastructure/deploy-full-stack.sh

# Deploy everything
./infrastructure/deploy-full-stack.ps1 my-webapp ./frontend ./backend ~/.ssh/my-key.pem
```

### 4. Access Your Application

Get the CloudFront URL:
```bash
aws cloudformation describe-stacks \
  --stack-name my-webapp \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
  --output text
```
Update alb to point to ec2 instance

### List cloudfront distributions
aws cloudfront list-distributions --query 'DistributionList.Items[*].[DomainName,Origins.Items[0].DomainName,Comment]' --output table
-------------------------------------------------------------------------------------------------------------
|                                             ListDistributions                                             |
+--------------------------------+---------------------------------------------------+----------------------+
|  d1vw6971tkz2ev.cloudfront.net |  dev-webapp-static-684039303263.s3.amazonaws.com  |  dev Svelte Frontend |
|  d2isf2i5dhn0ft.cloudfront.net |  dev-alb-2042808171.us-east-1.elb.amazonaws.com   |                      |
+--------------------------------+---------------------------------------------------+----------------------+
Update .env.production
VITE_API_URL=https://d2isf2i5dhn0ft.cloudfront.net

browser -> https://d1vw6971tkz2ev.cloudfront.net/


## 🛠️ Development Workflow

### Using Make Commands

```bash
# View all available commands
make help

# Local development
make dev-frontend    # Start Svelte dev server
make dev-backend     # Start Go backend

# Build for production
make build-frontend  # Build Svelte
make build-backend   # Build Go binary

# Deploy
make deploy          # Deploy everything
make deploy-frontend # Frontend only
make deploy-backend  # Backend only

# Stack management
make stack-outputs   # View all outputs
make stack-delete    # Delete entire stack
```

### Manual Development

#### Frontend:
```bash
cd frontend
npm run dev
# Runs on http://localhost:5173
# API proxied to localhost:8080
```

#### Backend:
```bash
cd backend
export REDIS_ENDPOINT=localhost
export REDIS_PORT=6379
go run main.go
# Runs on http://localhost:8080
```

## 📝 File Descriptions

### Infrastructure Files

**webapp-svelte-go.yaml**
- Complete CloudFormation template
- Configures all AWS resources
- Production-ready with security best practices

**deploy-full-stack.sh**
- Automated deployment script
- Builds frontend and backend
- Uploads to AWS
- Restarts services

### Backend Files

**main.go**
- Complete Go HTTP server
- AWS SDK v2 integration
- Redis caching layer
- DynamoDB operations
- S3 file operations
- Health check endpoint
- RESTful API structure

**go.mod**
- Go module dependencies
- AWS SDK packages
- HTTP router (chi)
- Redis client

### Frontend Files

**vite.config.ts**
- Vite build configuration
- Development proxy setup
- Production optimizations
- Code splitting

**svelte.config.js**
- SvelteKit configuration
- Static adapter for S3
- Prerendering setup
- Path aliases

**tsconfig.json**
- TypeScript configuration
- Strict type checking
- Path mappings

**api.ts**
- TypeScript API client
- Type-safe HTTP requests
- Error handling
- All backend endpoints

## 🔧 Configuration

### Environment Variables

Backend automatically receives:
```bash
S3_BUCKET_DATA        # Data storage bucket
S3_BUCKET_STATIC      # Frontend assets bucket
DYNAMODB_TABLE        # DynamoDB table name
REDIS_ENDPOINT        # Redis hostname
REDIS_PORT           # Redis port
AWS_REGION           # AWS region
ENVIRONMENT          # Environment name
PORT                 # Server port (8080)
```

Frontend `.env`:
```bash
VITE_API_URL=https://your-cloudfront-url.com/api
VITE_ENVIRONMENT=production
```

### CloudFormation Parameters

- `EnvironmentName`: Environment prefix (dev/staging/prod)
- `InstanceType`: EC2 instance type
- `KeyName`: SSH key pair name
- `SSHLocation`: Allowed IP for SSH
- `RedisNodeType`: Redis instance type

## 📊 API Endpoints

### Items (DynamoDB)
- `POST /api/items` - Create item
- `GET /api/items/:id` - Get item (with caching)
- `GET /api/items` - List items
- `PUT /api/items/:id` - Update item
- `DELETE /api/items/:id` - Delete item

### Cache (Redis)
- `POST /api/cache` - Set cache value
- `GET /api/cache/:key` - Get cached value
- `DELETE /api/cache/:key` - Delete cache

### Files (S3)
- `POST /api/upload` - Upload file
- `GET /api/files` - List files

### Health
- `GET /health` - Health check

## 🔐 Security Features

- ✅ VPC with public/private subnets
- ✅ Security groups with least privilege
- ✅ IAM roles for EC2 (no hardcoded credentials)
- ✅ S3 encryption at rest
- ✅ HTTPS via CloudFront
- ✅ DynamoDB point-in-time recovery
- ✅ Redis in private subnet

## 💰 Cost Optimization

### Development:
```bash
# Use smaller instance types
InstanceType=t3.micro
RedisNodeType=cache.t3.micro
```

### Stop when not in use:
```bash
# Stop EC2 instance
aws ec2 stop-instances --instance-ids <instance-id>
```

### Estimated Monthly Costs:
- **Development**: ~$30-50/month
- **Production**: ~$100-200/month
  - t3.medium EC2: ~$30
  - cache.t3.micro: ~$12
  - ALB: ~$16
  - CloudFront: ~$1-10 (usage based)
  - DynamoDB: Pay per request
  - S3: Pay per storage/requests

## 🔄 CI/CD with GitHub Actions

The included workflow (`/.github/workflows/deploy.yml`):
1. Builds frontend and backend
2. Runs tests
3. Deploys to AWS on push to main
4. Invalidates CloudFront cache
5. Restarts backend service

### Setup:
Add these secrets to your GitHub repo:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `EC2_SSH_PRIVATE_KEY`
- `CLOUDFRONT_URL`

## 📚 Additional Resources

- [SETUP_GUIDE.md](./SETUP_GUIDE.md) - Detailed setup instructions
- [API_DOCUMENTATION.md](./API_DOCUMENTATION.md) - API reference (for Node.js example)
- [SvelteKit Docs](https://kit.svelte.dev/)
- [Go AWS SDK](https://aws.github.io/aws-sdk-go-v2/)
- [AWS CloudFormation](https://docs.aws.amazon.com/cloudformation/)

## 🆘 Troubleshooting

### Frontend not loading
```bash
# Check CloudFront distribution status
aws cloudfront get-distribution --id <dist-id>

# Verify S3 bucket contents
aws s3 ls s3://<bucket-name>/
```

### Backend API errors
```bash
# View backend logs
ssh -i key.pem ec2-user@<ip> 'sudo journalctl -u backend -f'

# Check service status
ssh -i key.pem ec2-user@<ip> 'sudo systemctl status backend'
```

### Cannot connect to Redis
- Redis is in private subnet
- Only accessible from EC2 instance
- Test from EC2: `redis-cli -h <endpoint>`

## 🗑️ Cleanup

To delete everything:

```bash
# Empty S3 buckets
make stack-delete

# Or manually:
aws s3 rm s3://<static-bucket> --recursive
aws s3 rm s3://<data-bucket> --recursive
aws cloudformation delete-stack --stack-name my-webapp
```

## 📄 License

This template is provided as-is for your use. Customize as needed for your application.

## 🤝 Contributing

This is a template project. Feel free to adapt it for your needs!

---

**Need Help?** 
- Check the [SETUP_GUIDE.md](./SETUP_GUIDE.md) for detailed instructions
- Review AWS CloudFormation documentation
- Test locally before deploying to AWS
