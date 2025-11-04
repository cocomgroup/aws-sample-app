# Svelte + Go Web Application on AWS

Complete guide to deploying your TypeScript/Svelte frontend and Go backend to AWS using CloudFormation.

## Architecture Overview

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│   Users     │─────▶│  CloudFront  │─────▶│  S3 Bucket  │
│             │      │     (CDN)    │      │  (Svelte)   │
└─────────────┘      └──────────────┘      └─────────────┘
                            │
                            │ /api/*
                            ▼
                     ┌──────────────┐
                     │     ALB      │
                     │ Load Balancer│
                     └──────────────┘
                            │
                            ▼
                     ┌──────────────┐      ┌─────────────┐
                     │   EC2 + Go   │─────▶│   Redis     │
                     │   Backend    │      │  (Cache)    │
                     └──────────────┘      └─────────────┘
                            │
                            ├─────────────▶ S3 (Data)
                            │
                            └─────────────▶ DynamoDB
```

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** installed and configured
3. **Node.js** 18+ and npm/pnpm
4. **Go** 1.21+
5. **EC2 Key Pair** created in your AWS region

## Project Structure

```
your-project/
├── frontend/              # Svelte + TypeScript
│   ├── src/
│   │   ├── routes/
│   │   ├── lib/
│   │   │   └── api.ts    # API client
│   │   └── app.html
│   ├── static/
│   ├── svelte.config.js
│   ├── vite.config.ts
│   ├── tsconfig.json
│   └── package.json
│
├── backend/               # Go API
│   ├── main.go
│   ├── go.mod
│   └── go.sum
│
└── infrastructure/        # AWS CloudFormation
    ├── webapp-svelte-go.yaml
    ├── deploy-full-stack.sh
    └── README.md
```

## Step 1: Set Up Your Frontend (Svelte)

### 1.1 Create or Configure Your Svelte Project

If starting fresh:
```bash
npm create svelte@latest frontend
cd frontend
npm install
```

### 1.2 Install Required Dependencies

```bash
npm install -D @sveltejs/adapter-static
```

### 1.3 Configure SvelteKit for Static Deployment

Copy the provided `svelte.config.js`:
- Uses `@sveltejs/adapter-static` for S3 deployment
- Outputs to `build` directory
- Enables SPA fallback for client-side routing

### 1.4 Configure Vite

Copy the provided `vite.config.ts`:
- Proxies `/api` requests to backend during development
- Optimizes build for production
- Removes console logs in production

### 1.5 Set Up API Client

Copy the provided `src/lib/api.ts`:
- TypeScript API client
- Handles all backend communication
- Type-safe interfaces

### 1.6 Update Your Routes

Example route (`src/routes/+page.svelte`):
```svelte
<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api';
	
	let items = [];
	let loading = true;
	
	onMount(async () => {
		const result = await api.listItems();
		if (result.data) {
			items = result.data.items;
		}
		loading = false;
	});
</script>

<h1>My Items</h1>

{#if loading}
	<p>Loading...</p>
{:else if items.length > 0}
	<ul>
		{#each items as item}
			<li>{item.id}: {JSON.stringify(item.data)}</li>
		{/each}
	</ul>
{:else}
	<p>No items found</p>
{/if}
```

### 1.7 Build Frontend

```bash
npm run build
```

This creates a `build` directory with your static assets.

## Step 2: Set Up Your Backend (Go)

### 2.1 Create or Configure Your Go Project

```bash
mkdir backend
cd backend
go mod init github.com/yourusername/webapp-backend
```

### 2.2 Copy Example Files

Copy the provided files:
- `main.go` - Complete Go backend with AWS integrations
- `go.mod` - Dependencies

### 2.3 Install Dependencies

```bash
go mod tidy
go mod download
```

### 2.4 Test Locally

```bash
# Set environment variables
export S3_BUCKET_DATA=test-bucket
export DYNAMODB_TABLE=test-table
export REDIS_ENDPOINT=localhost
export REDIS_PORT=6379
export PORT=8080

# Run
go run main.go
```

### 2.5 Build for Production

```bash
# Build for Linux (EC2 runs Linux)
GOOS=linux GOARCH=amd64 go build -o backend -ldflags="-s -w" .
```

## Step 3: Deploy AWS Infrastructure

### 3.1 Validate CloudFormation Template

```bash
aws cloudformation validate-template \
  --template-body file://webapp-svelte-go.yaml
```

### 3.2 Deploy Stack

```bash
aws cloudformation create-stack \
  --stack-name my-webapp \
  --template-body file://webapp-svelte-go.yaml \
  --parameters \
    ParameterKey=EnvironmentName,ParameterValue=prod \
    ParameterKey=InstanceType,ParameterValue=t3.medium \
    ParameterKey=KeyName,ParameterValue=YOUR_KEY_PAIR_NAME \
    ParameterKey=SSHLocation,ParameterValue=YOUR_IP/32 \
  --capabilities CAPABILITY_IAM \
  --region us-east-1
```

### 3.3 Wait for Completion

```bash
aws cloudformation wait stack-create-complete --stack-name my-webapp
```

This takes 10-15 minutes. Monitor progress:
```bash
aws cloudformation describe-stack-events --stack-name my-webapp
```

### 3.4 Get Stack Outputs

```bash
aws cloudformation describe-stacks \
  --stack-name my-webapp \
  --query 'Stacks[0].Outputs'
```

Save these values:
- `CloudFrontURL` - Your application URL
- `BackendInstancePublicIP` - For SSH access
- `StaticAssetsBucket` - S3 bucket name
- `CloudFrontDistributionId` - For cache invalidation

## Step 4: Deploy Your Application

### Option A: Automated Deployment (Recommended)

```bash
chmod +x deploy-full-stack.sh

./deploy-full-stack.sh \
  my-webapp \
  ./frontend \
  ./backend \
  ~/.ssh/my-key.pem
```

This script will:
1. Build your Svelte frontend
2. Deploy to S3
3. Invalidate CloudFront cache
4. Compile Go backend
5. Deploy to EC2
6. Start the backend service

### Option B: Manual Deployment

#### Deploy Frontend:
```bash
# Build
cd frontend
npm run build

# Deploy to S3
aws s3 sync build/ s3://YOUR_BUCKET_NAME/ --delete

# Invalidate CloudFront
aws cloudfront create-invalidation \
  --distribution-id YOUR_DISTRIBUTION_ID \
  --paths "/*"
```

#### Deploy Backend:
```bash
# Build
cd backend
GOOS=linux GOARCH=amd64 go build -o backend .

# Upload to EC2
scp -i YOUR_KEY.pem backend ec2-user@YOUR_EC2_IP:/opt/webapp/

# Start service
ssh -i YOUR_KEY.pem ec2-user@YOUR_EC2_IP \
  'sudo systemctl restart backend'
```

## Step 5: Verify Deployment

### Check Backend Health

```bash
# Via EC2 directly
curl http://YOUR_EC2_IP:8080/health

# Via CloudFront
curl https://YOUR_CLOUDFRONT_URL/api/health
```

### Access Your Application

Open in browser:
```
https://YOUR_CLOUDFRONT_URL
```

## Development Workflow

### Local Development

#### Terminal 1 - Backend:
```bash
cd backend
export REDIS_ENDPOINT=localhost
export REDIS_PORT=6379
go run main.go
# Backend running on http://localhost:8080
```

#### Terminal 2 - Frontend:
```bash
cd frontend
npm run dev
# Frontend running on http://localhost:5173
# API calls proxied to localhost:8080
```

### Deploy Updates

#### Frontend Only:
```bash
cd frontend
npm run build
aws s3 sync build/ s3://YOUR_BUCKET/ --delete
aws cloudfront create-invalidation --distribution-id YOUR_DIST_ID --paths "/*"
```

#### Backend Only:
```bash
cd backend
GOOS=linux GOARCH=amd64 go build -o backend .
scp -i YOUR_KEY.pem backend ec2-user@YOUR_EC2_IP:/opt/webapp/
ssh -i YOUR_KEY.pem ec2-user@YOUR_EC2_IP 'sudo systemctl restart backend'
```

## Environment Variables

### Backend (automatically configured via CloudFormation):
- `S3_BUCKET_DATA` - S3 bucket for data storage
- `S3_BUCKET_STATIC` - S3 bucket for frontend
- `DYNAMODB_TABLE` - DynamoDB table name
- `REDIS_ENDPOINT` - Redis endpoint
- `REDIS_PORT` - Redis port (6379)
- `AWS_REGION` - AWS region
- `ENVIRONMENT` - Environment name
- `PORT` - Server port (8080)

### Frontend (create `.env` in frontend directory):
```env
VITE_API_URL=https://YOUR_CLOUDFRONT_URL/api
VITE_ENVIRONMENT=production
```

## Monitoring & Debugging

### View Backend Logs
```bash
ssh -i YOUR_KEY.pem ec2-user@YOUR_EC2_IP \
  'sudo journalctl -u backend -f'
```

### Check Service Status
```bash
ssh -i YOUR_KEY.pem ec2-user@YOUR_EC2_IP \
  'sudo systemctl status backend'
```

### CloudFront Logs
Enable logging in CloudFront settings via AWS Console.

### CloudWatch
Metrics are automatically sent to CloudWatch for EC2, ALB, and DynamoDB.

## Cost Optimization

### Development Environment
```bash
aws cloudformation update-stack \
  --stack-name my-webapp \
  --use-previous-template \
  --parameters \
    ParameterKey=EnvironmentName,ParameterValue=dev \
    ParameterKey=InstanceType,ParameterValue=t3.micro \
    ParameterKey=RedisNodeType,ParameterValue=cache.t3.micro \
  --capabilities CAPABILITY_IAM
```

### Stop When Not In Use
```bash
# Stop EC2 instance
aws ec2 stop-instances --instance-ids YOUR_INSTANCE_ID

# Start when needed
aws ec2 start-instances --instance-ids YOUR_INSTANCE_ID
```

## Cleanup

To delete everything:

```bash
# Empty S3 buckets first
aws s3 rm s3://YOUR_STATIC_BUCKET --recursive
aws s3 rm s3://YOUR_DATA_BUCKET --recursive

# Delete CloudFormation stack
aws cloudformation delete-stack --stack-name my-webapp

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name my-webapp
```

## Troubleshooting

### Frontend not loading
1. Check CloudFront distribution status (must be "Deployed")
2. Verify S3 bucket policy allows public reads
3. Check browser console for errors

### API calls failing
1. Verify backend is running: `sudo systemctl status backend`
2. Check backend logs: `sudo journalctl -u backend -f`
3. Test health endpoint directly
4. Verify security group allows traffic on port 8080

### Cannot SSH to EC2
1. Check security group allows your IP
2. Verify key file permissions: `chmod 400 key.pem`
3. Use correct username: `ec2-user`

### Redis connection errors
1. Redis is in private subnet (cannot access directly)
2. Only accessible from EC2 instance
3. Check Redis cluster status in AWS Console

## Security Best Practices

1. **SSH Access**: Restrict to your IP only
2. **HTTPS**: Use ACM certificate for custom domain
3. **Secrets**: Use AWS Secrets Manager for sensitive data
4. **IAM Roles**: Follow principle of least privilege
5. **Monitoring**: Enable CloudWatch alarms

## Next Steps

1. **Custom Domain**: Configure Route 53 and ACM certificate
2. **CI/CD**: Set up GitHub Actions or AWS CodePipeline
3. **Auto Scaling**: Add Auto Scaling Group for backend
4. **Monitoring**: Configure CloudWatch dashboards
5. **Backups**: Enable automated DynamoDB backups
6. **WAF**: Add AWS WAF for additional security

## Support

- AWS CloudFormation: https://docs.aws.amazon.com/cloudformation/
- SvelteKit: https://kit.svelte.dev/docs
- Go AWS SDK: https://aws.github.io/aws-sdk-go-v2/docs/

## License

This template is provided as-is for your use.
