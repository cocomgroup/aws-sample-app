# deploy-full-stack.ps1 - PowerShell version for Windows
# Deploy Svelte frontend and Go backend to AWS

param(
    [Parameter(Mandatory=$true)]
    [string]$StackName,
    
    [Parameter(Mandatory=$true)]
    [string]$FrontendDir,
    
    [Parameter(Mandatory=$true)]
    [string]$BackendDir,
    
    [Parameter(Mandatory=$false)]
    [string]$KeyFile = ""
)

Write-Host "=== Full Stack Deployment (Svelte + Go) ===" -ForegroundColor Green
Write-Host ""

# Check if directories exist
if (-not (Test-Path $FrontendDir)) {
    Write-Host "Error: Frontend directory not found: $FrontendDir" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $BackendDir)) {
    Write-Host "Error: Backend directory not found: $BackendDir" -ForegroundColor Red
    exit 1
}

Write-Host "Getting stack outputs..." -ForegroundColor Blue

# Get stack outputs
$outputs = aws cloudformation describe-stacks --stack-name $StackName --query 'Stacks[0].Outputs' --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Could not get stack outputs. Is the stack deployed?" -ForegroundColor Red
    exit 1
}

# Extract values
$staticBucket = ($outputs | Where-Object {$_.OutputKey -eq "StaticAssetsBucket"}).OutputValue
$cloudfrontId = ($outputs | Where-Object {$_.OutputKey -eq "CloudFrontDistributionId"}).OutputValue
$cloudfrontUrl = ($outputs | Where-Object {$_.OutputKey -eq "CloudFrontURL"}).OutputValue
$backendIp = ($outputs | Where-Object {$_.OutputKey -eq "BackendInstancePublicIP"}).OutputValue
$albEndpoint = ($outputs | Where-Object {$_.OutputKey -eq "ALBEndpoint"}).OutputValue

Write-Host "Stack outputs retrieved" -ForegroundColor Green
Write-Host "  Static Bucket: $staticBucket"
Write-Host "  CloudFront ID: $cloudfrontId"
Write-Host "  CloudFront URL: $cloudfrontUrl"
Write-Host "  Backend IP: $backendIp"
Write-Host "  ALB Endpoint: $albEndpoint"
Write-Host ""

# ==========================================
# Deploy Frontend (Svelte)
# ==========================================
Write-Host "Step 1: Building Svelte frontend..." -ForegroundColor Green

Push-Location $FrontendDir

# Check if package.json exists
if (-not (Test-Path "package.json")) {
    Write-Host "Error: package.json not found in frontend directory" -ForegroundColor Red
    Pop-Location
    exit 1
}

# Create .env file
@"
VITE_API_URL=https://$cloudfrontUrl/api
VITE_ENVIRONMENT=production
"@ | Out-File -FilePath ".env" -Encoding UTF8

Write-Host "Installing dependencies..." -ForegroundColor Yellow
npm install

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: npm install failed" -ForegroundColor Red
    Pop-Location
    exit 1
}

Write-Host "Building production bundle..." -ForegroundColor Yellow
npm run build

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: npm build failed" -ForegroundColor Red
    Pop-Location
    exit 1
}

# Determine build directory
$buildDir = "dist"
if (Test-Path "build") {
    $buildDir = "build"
}

if (-not (Test-Path $buildDir)) {
    Write-Host "Error: Build directory ($buildDir) not found" -ForegroundColor Red
    Pop-Location
    exit 1
}

Write-Host "Frontend built successfully" -ForegroundColor Green

Write-Host "Step 2: Deploying frontend to S3..." -ForegroundColor Green

# Sync to S3 (with cache control for assets)
aws s3 sync $buildDir s3://$staticBucket/ --delete `
    --cache-control "public, max-age=31536000, immutable" `
    --exclude "*.html" `
    --exclude "*.json"

# Upload HTML files with shorter cache
aws s3 sync $buildDir s3://$staticBucket/ `
    --cache-control "public, max-age=0, must-revalidate" `
    --exclude "*" `
    --include "*.html" `
    --include "*.json"

Write-Host "Frontend deployed to S3" -ForegroundColor Green

Write-Host "Step 3: Invalidating CloudFront cache..." -ForegroundColor Green
$invalidationId = (aws cloudfront create-invalidation `
    --distribution-id $cloudfrontId `
    --paths "/*" `
    --query 'Invalidation.Id' `
    --output text)

Write-Host "CloudFront invalidation created: $invalidationId" -ForegroundColor Green

Pop-Location

# ==========================================
# Deploy Backend (Go)
# ==========================================
Write-Host "Step 4: Building Go backend..." -ForegroundColor Green

Push-Location $BackendDir

# Check if main.go exists
if (-not (Test-Path "main.go") -and -not (Test-Path "cmd/main.go") -and -not (Test-Path "cmd/server/main.go")) {
    Write-Host "Error: main.go not found in backend directory" -ForegroundColor Red
    Pop-Location
    exit 1
}

Write-Host "Compiling Go binary for Linux..." -ForegroundColor Yellow

# Build for Linux
$env:GOOS = "linux"
$env:GOARCH = "amd64"
go build -o backend -ldflags="-s -w" .

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Go build failed" -ForegroundColor Red
    Pop-Location
    exit 1
}

if (-not (Test-Path "backend")) {
    Write-Host "Error: Backend binary not created" -ForegroundColor Red
    Pop-Location
    exit 1
}

$binarySize = (Get-Item "backend").Length / 1MB
Write-Host "Backend compiled successfully" -ForegroundColor Green
Write-Host "  Binary size: $([math]::Round($binarySize, 2)) MB"

Pop-Location

# ==========================================
# Deploy to EC2
# ==========================================
if ($KeyFile -ne "") {
    Write-Host "Step 5: Deploying backend to EC2..." -ForegroundColor Green
    
    if (-not (Test-Path $KeyFile)) {
        Write-Host "Error: Key file not found: $KeyFile" -ForegroundColor Red
        exit 1
    }
    
    $ecUser = "ec2-user"
    $remoteDir = "/opt/webapp"
    
    Write-Host "Testing SSH connection..." -ForegroundColor Yellow
    ssh -i $KeyFile -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$ecUser@$backendIp" "echo 'Connection successful'"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to connect to EC2 instance" -ForegroundColor Red
        exit 1
    }

    # Stop the service if it's running
    Write-Host "Stopping backend service..."
    ssh -i $KeyFile -o StrictHostKeyChecking=no ec2-user@$backendIp "sudo systemctl stop backend || true"

    Write-Host "Creating application directory..."
    ssh -i $KeyFile -o StrictHostKeyChecking=no "$ecUser@$backendIp" "sudo mkdir -p $remoteDir && sudo chown ec2-user:ec2-user $remoteDir"

    Write-Host "Uploading backend binary..." -ForegroundColor Yellow
    scp -i $KeyFile "$BackendDir/backend" "$ecUser@${backendIp}:$remoteDir/"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to upload backend binary" -ForegroundColor Red
        exit 1
    }

    Write-Host "Setting up backend service..."
    ssh -i $KeyFile -o StrictHostKeyChecking=no ec2-user@$backendIp @"
    sudo tee /etc/systemd/system/backend.service > /dev/null <<'EOF'
[Unit]
Description=Backend API Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/webapp
ExecStart=/opt/webapp/backend
Restart=always
RestartSec=5
Environment='PORT=8080'

StandardOutput=journal
StandardError=journal
SyslogIdentifier=backend

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable backend
    sudo systemctl restart backend
"@

    Write-Host "Checking backend service status..."
    ssh -i $KeyFile -o StrictHostKeyChecking=no ec2-user@$backendIp "sudo systemctl status backend --no-pager"    
 
    Write-Host "Setting permissions and restarting service..." -ForegroundColor Yellow
    ssh -i $KeyFile "$ecUser@$backendIp" @"
sudo chmod +x $remoteDir/backend
sudo systemctl daemon-reload
sudo systemctl restart backend
sudo systemctl enable backend

# Wait for service to start
Start-Sleep -Seconds 3

# Check service status
sudo systemctl status backend --no-pager

# Test health endpoint
Write-Host ""
Write-Host "Testing health endpoint..."
curl -f http://localhost:8080/health
"@

   Write-Host "Installing Redis service..." -ForegroundColor Yellow
    ssh -i $KeyFile "$ecUser@$backendIp" @"
sudo dnf install redis6 -y
sudo systemctl start redis6
sudo systemctl enable redis6
sudo systemctl status redis6
sudo systemctl restart backend
"@

    Write-Host "Backend deployed and running" -ForegroundColor Green
} else {
    Write-Host "Step 5: Skipping EC2 deployment (no key file provided)" -ForegroundColor Yellow
    Write-Host "Backend binary available at: $BackendDir\backend" -ForegroundColor Yellow
    Write-Host "To deploy manually:" -ForegroundColor Yellow
    Write-Host "  scp -i YOUR_KEY backend ec2-user@{$backendIp}:/opt/webapp/"
    Write-Host "  ssh -i YOUR_KEY ec2-user@{$backendIp} 'sudo systemctl restart backend'"
}

# ==========================================
# Summary
# ==========================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "           Deployment Complete!            " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Frontend:" -ForegroundColor Blue
Write-Host "  URL: $cloudfrontUrl" -ForegroundColor Green
Write-Host "  S3 Bucket: $staticBucket"
Write-Host "  CloudFront Invalidation: $invalidationId"
Write-Host ""
Write-Host "Backend:" -ForegroundColor Blue
Write-Host "  EC2 Instance: $backendIp"
Write-Host "  Load Balancer: http://$albEndpoint"
Write-Host "  API Endpoint: $cloudfrontUrl/api"
Write-Host ""

if ($KeyFile -ne "") {
    Write-Host "Useful Commands:" -ForegroundColor Blue
    Write-Host "  View logs:    ssh -i $KeyFile ec2-user@$backendIp 'sudo journalctl -u backend -f'"
    Write-Host "  Restart API:  ssh -i $KeyFile ec2-user@$backendIp 'sudo systemctl restart backend'"
    Write-Host "  Check status: ssh -i $KeyFile ec2-user@$backendIp 'sudo systemctl status backend'"
}

Write-Host ""
Write-Host "Your Svelte + Go application is live!" -ForegroundColor Green
