# Quick Reference Commands

## 🚀 Initial Deployment

### 1. Deploy Infrastructure
```bash
aws cloudformation create-stack \
  --stack-name my-webapp-prod \
  --template-body file://svelte-go-infrastructure.yaml \
  --parameters \
    ParameterKey=EnvironmentName,ParameterValue=prod \
    ParameterKey=InstanceType,ParameterValue=t3.medium \
    ParameterKey=KeyName,ParameterValue=YOUR_KEY_PAIR_NAME \
    ParameterKey=SSHLocation,ParameterValue=YOUR_IP/32 \
  --capabilities CAPABILITY_IAM \
  --region us-east-1

aws cloudformation wait stack-create-complete --stack-name my-webapp-prod
```

### 2. Get Stack Outputs
```bash
aws cloudformation describe-stacks \
  --stack-name my-webapp-prod \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table
```

### 3. Deploy Application
```bash
chmod +x deploy-svelte-go.sh
./deploy-svelte-go.sh <EC2_IP> <KEY_FILE> <PROJECT_DIR>
```

## 🔧 Daily Operations

### SSH into Server
```bash
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP>
```

### View Logs
```bash
# Backend logs
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo journalctl -u go-backend -f'

# Backend error logs
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'tail -f /var/log/webapp/backend-error.log'

# Nginx access logs
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo tail -f /var/log/nginx/access.log'

# Nginx error logs
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo tail -f /var/log/nginx/error.log'
```

### Service Management
```bash
# Restart backend
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo systemctl restart go-backend'

# Stop backend
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo systemctl stop go-backend'

# Start backend
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo systemctl start go-backend'

# Check backend status
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo systemctl status go-backend'

# Restart Nginx
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo systemctl restart nginx'

# Test Nginx config
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo nginx -t'
```

### Health Checks
```bash
# Application health
curl http://<EC2_IP>/health

# Backend API health
curl http://<EC2_IP>/api/health

# Full test with headers
curl -I http://<EC2_IP>
```

## 🔄 Updates & Redeployment

### Quick Update (Code Only)
```bash
./deploy-svelte-go.sh <EC2_IP> <KEY_FILE> <PROJECT_DIR>
```

### Update Environment Variables
```bash
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP>
sudo nano /etc/sysconfig/go-backend
# Edit variables
sudo systemctl restart go-backend
```

### Update Infrastructure (Stack Update)
```bash
aws cloudformation update-stack \
  --stack-name my-webapp-prod \
  --template-body file://svelte-go-infrastructure.yaml \
  --parameters \
    ParameterKey=InstanceType,ParameterValue=t3.large \
  --capabilities CAPABILITY_IAM
```

## 🗑️ Cleanup

### Delete Stack
```bash
# Empty S3 buckets first
aws s3 rm s3://YOUR-BUCKET-NAME --recursive

# Delete stack
aws cloudformation delete-stack --stack-name my-webapp-prod

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name my-webapp-prod
```

## 🐛 Debugging

### Check Backend Process
```bash
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'ps aux | grep webapp-server'
```

### Check Listening Ports
```bash
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo netstat -tlnp | grep -E "(80|8080)"'
```

### Test Backend Directly
```bash
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'curl http://localhost:8080/health'
```

### Check Disk Space
```bash
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'df -h'
```

### Check Memory Usage
```bash
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'free -h'
```

### View System Load
```bash
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'uptime'
```

## 📊 AWS Service Operations

### DynamoDB
```bash
# List items
aws dynamodb scan --table-name prod-webapp-table --max-items 10

# Get item
aws dynamodb get-item \
  --table-name prod-webapp-table \
  --key '{"pk": {"S": "user123"}, "sk": {"S": "ITEM#123"}}'
```

### S3
```bash
# List buckets
aws s3 ls

# List objects
aws s3 ls s3://your-bucket-name

# Upload file
aws s3 cp file.txt s3://your-bucket-name/

# Download file
aws s3 cp s3://your-bucket-name/file.txt ./
```

### ElastiCache (Redis)
```bash
# Connect to Redis from EC2
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP>
redis-cli -h $REDIS_ENDPOINT -p $REDIS_PORT

# Test Redis
redis-cli -h $REDIS_ENDPOINT -p $REDIS_PORT ping
```

## 🔒 Security Operations

### Update Security Group
```bash
# Get security group ID
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=prod-web-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text

# Add your IP
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_IP/32
```

### Rotate SSH Keys
```bash
# Generate new key pair
aws ec2 create-key-pair \
  --key-name my-new-key \
  --query 'KeyMaterial' \
  --output text > my-new-key.pem

chmod 400 my-new-key.pem
```

## 📈 Monitoring

### CloudWatch Logs
```bash
# List log groups
aws logs describe-log-groups

# Tail logs
aws logs tail /aws/ec2/my-webapp --follow
```

### Get Instance Metrics
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=i-xxxxx \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

## 🔄 Backup & Recovery

### Backup DynamoDB Table
```bash
aws dynamodb create-backup \
  --table-name prod-webapp-table \
  --backup-name prod-webapp-backup-$(date +%Y%m%d)
```

### Create AMI Snapshot
```bash
aws ec2 create-image \
  --instance-id i-xxxxx \
  --name "webapp-backup-$(date +%Y%m%d)" \
  --description "Backup of web application"
```

## 📱 Common Tasks

### Update Go Dependencies
```bash
cd backend
go get -u ./...
go mod tidy
```

### Update Frontend Dependencies
```bash
cd frontend
npm update
npm audit fix
```

### Build Locally
```bash
# Frontend
cd frontend && npm run build

# Backend
cd backend && GOOS=linux GOARCH=amd64 go build -o webapp-server .
```

## 🎯 Performance Optimization

### Enable Gzip in Nginx
Already configured in deployment!

### Cache Static Assets
Already configured with 1-year cache headers!

### Monitor Response Times
```bash
# Test endpoint response time
time curl http://<EC2_IP>/api/items
```

### Redis Cache Hit Rate
```bash
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP>
redis-cli -h $REDIS_ENDPOINT -p $REDIS_PORT info stats | grep hits
```

## 🆘 Emergency Procedures

### Application Down
```bash
# 1. Check backend service
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo systemctl status go-backend'

# 2. Check logs
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo journalctl -u go-backend -n 50'

# 3. Restart
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo systemctl restart go-backend'
```

### High Memory Usage
```bash
# Check process memory
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'top -b -n 1 | head -20'

# Restart backend if needed
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo systemctl restart go-backend'
```

### Disk Full
```bash
# Check disk usage
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'df -h'

# Clear logs
ssh -i ~/.ssh/my-key.pem ec2-user@<EC2_IP> 'sudo journalctl --vacuum-time=7d'
```
