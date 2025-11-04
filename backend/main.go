package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/go-redis/redis/v8"
)

var (
	// AWS clients
	s3Client      *s3.Client
	dynamoClient  *dynamodb.Client
	redisClient   *redis.Client
	
	// Config from environment
	s3BucketData     string
	s3BucketStatic   string
	dynamoTableName  string
	redisEndpoint    string
	redisPort        string
	awsRegion        string
	environment      string
	port             string
)

type Server struct {
	router *chi.Mux
}

// HealthResponse represents the health check response
type HealthResponse struct {
	Status    string            `json:"status"`
	Timestamp time.Time         `json:"timestamp"`
	Services  map[string]string `json:"services"`
}

// Item represents a DynamoDB item
type Item struct {
	ID        string                 `json:"id" dynamodbav:"id"`
	Timestamp int64                  `json:"timestamp" dynamodbav:"timestamp"`
	Data      map[string]interface{} `json:"data" dynamodbav:"data"`
	CreatedAt string                 `json:"createdAt" dynamodbav:"createdAt"`
}

func init() {
	// Load environment variables
	s3BucketData = os.Getenv("S3_BUCKET_DATA")
	s3BucketStatic = os.Getenv("S3_BUCKET_STATIC")
	dynamoTableName = os.Getenv("DYNAMODB_TABLE")
	redisEndpoint = os.Getenv("REDIS_ENDPOINT")
	redisPort = getEnvDefault("REDIS_PORT", "6379")
	awsRegion = getEnvDefault("AWS_REGION", "us-east-1")
	environment = getEnvDefault("ENVIRONMENT", "prod")
	port = getEnvDefault("PORT", "8080")
}

func main() {
	// Initialize AWS clients
	ctx := context.Background()
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(awsRegion))
	if err != nil {
		log.Fatalf("Unable to load AWS SDK config: %v", err)
	}

	s3Client = s3.NewFromConfig(cfg)
	dynamoClient = dynamodb.NewFromConfig(cfg)

	// Initialize Redis client
	redisClient = redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", redisEndpoint, redisPort),
		Password: "",
		DB:       0,
	})

	// Test Redis connection
	if err := redisClient.Ping(ctx).Err(); err != nil {
		log.Printf("Warning: Redis connection failed: %v", err)
	} else {
		log.Println("✓ Connected to Redis")
	}

	// Create and configure server
	server := &Server{
		router: chi.NewRouter(),
	}

	server.setupMiddleware()
	server.setupRoutes()

	// Start server
	addr := fmt.Sprintf(":%s", port)
	log.Printf("🚀 Server starting on %s", addr)
	log.Printf("   Environment: %s", environment)
	log.Printf("   DynamoDB Table: %s", dynamoTableName)
	log.Printf("   S3 Data Bucket: %s", s3BucketData)
	log.Printf("   Redis: %s:%s", redisEndpoint, redisPort)

	if err := http.ListenAndServe(addr, server.router); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

func (s *Server) setupMiddleware() {
	s.router.Use(middleware.RequestID)
	s.router.Use(middleware.RealIP)
	s.router.Use(middleware.Logger)
	s.router.Use(middleware.Recoverer)
	s.router.Use(middleware.Timeout(60 * time.Second))

	// CORS configuration
	s.router.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"https://*", "http://*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))
}

func (s *Server) setupRoutes() {
	// Health check
	s.router.Get("/health", s.handleHealth)

	// API routes
	s.router.Route("/api", func(r chi.Router) {
		// Items endpoints
		r.Post("/items", s.handleCreateItem)
		r.Get("/items/{id}", s.handleGetItem)
		r.Get("/items", s.handleListItems)
		r.Put("/items/{id}", s.handleUpdateItem)
		r.Delete("/items/{id}", s.handleDeleteItem)

		// Cache endpoints
		r.Post("/cache", s.handleSetCache)
		r.Get("/cache/{key}", s.handleGetCache)
		r.Delete("/cache/{key}", s.handleDeleteCache)

		// S3 endpoints
		r.Post("/upload", s.handleUpload)
		r.Get("/files", s.handleListFiles)
	})
}

// Health check handler
func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	
	services := make(map[string]string)
	
	// Check Redis
	if err := redisClient.Ping(ctx).Err(); err != nil {
		services["redis"] = "unhealthy"
	} else {
		services["redis"] = "healthy"
	}
	
	services["dynamodb"] = dynamoTableName
	services["s3"] = s3BucketData
	
	response := HealthResponse{
		Status:    "healthy",
		Timestamp: time.Now(),
		Services:  services,
	}

	respondJSON(w, http.StatusOK, response)
}

// DynamoDB Handlers
func (s *Server) handleCreateItem(w http.ResponseWriter, r *http.Request) {
	var input struct {
		ID   string                 `json:"id"`
		Data map[string]interface{} `json:"data"`
	}

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		respondError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	item := Item{
		ID:        input.ID,
		Timestamp: time.Now().UnixMilli(),
		Data:      input.Data,
		CreatedAt: time.Now().UTC().Format(time.RFC3339),
	}

	av, err := attributevalue.MarshalMap(item)
	if err != nil {
		respondError(w, http.StatusInternalServerError, "Failed to marshal item")
		return
	}

	_, err = dynamoClient.PutItem(r.Context(), &dynamodb.PutItemInput{
		TableName: aws.String(dynamoTableName),
		Item:      av,
	})

	if err != nil {
		log.Printf("DynamoDB PutItem error: %v", err)
		respondError(w, http.StatusInternalServerError, "Failed to create item")
		return
	}

	respondJSON(w, http.StatusCreated, map[string]interface{}{
		"message": "Item created successfully",
		"item":    item,
	})
}

func (s *Server) handleGetItem(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	ctx := r.Context()

	// Check cache first
	cacheKey := fmt.Sprintf("item:%s", id)
	cached, err := redisClient.Get(ctx, cacheKey).Result()
	
	if err == nil {
		var item Item
		if json.Unmarshal([]byte(cached), &item) == nil {
			respondJSON(w, http.StatusOK, map[string]interface{}{
				"source": "cache",
				"item":   item,
			})
			return
		}
	}

	// Query DynamoDB
	result, err := dynamoClient.Query(ctx, &dynamodb.QueryInput{
		TableName:              aws.String(dynamoTableName),
		KeyConditionExpression: aws.String("id = :id"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":id": &types.AttributeValueMemberS{Value: id},
		},
		Limit:            aws.Int32(1),
		ScanIndexForward: aws.Bool(false),
	})

	if err != nil {
		log.Printf("DynamoDB Query error: %v", err)
		respondError(w, http.StatusInternalServerError, "Failed to query item")
		return
	}

	if len(result.Items) == 0 {
		respondError(w, http.StatusNotFound, "Item not found")
		return
	}

	var item Item
	if err := attributevalue.UnmarshalMap(result.Items[0], &item); err != nil {
		respondError(w, http.StatusInternalServerError, "Failed to unmarshal item")
		return
	}

	// Cache the result
	if itemJSON, err := json.Marshal(item); err == nil {
		redisClient.Set(ctx, cacheKey, itemJSON, 5*time.Minute)
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"source": "database",
		"item":   item,
	})
}

func (s *Server) handleListItems(w http.ResponseWriter, r *http.Request) {
	result, err := dynamoClient.Scan(r.Context(), &dynamodb.ScanInput{
		TableName: aws.String(dynamoTableName),
		Limit:     aws.Int32(20),
	})

	if err != nil {
		log.Printf("DynamoDB Scan error: %v", err)
		respondError(w, http.StatusInternalServerError, "Failed to list items")
		return
	}

	var items []Item
	if err := attributevalue.UnmarshalListOfMaps(result.Items, &items); err != nil {
		respondError(w, http.StatusInternalServerError, "Failed to unmarshal items")
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"count": len(items),
		"items": items,
	})
}

func (s *Server) handleUpdateItem(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	
	var input struct {
		Timestamp int64                  `json:"timestamp"`
		Data      map[string]interface{} `json:"data"`
	}

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		respondError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	dataAv, _ := attributevalue.Marshal(input.Data)
	updatedAtAv, _ := attributevalue.Marshal(time.Now().UTC().Format(time.RFC3339))

	_, err := dynamoClient.UpdateItem(r.Context(), &dynamodb.UpdateItemInput{
		TableName: aws.String(dynamoTableName),
		Key: map[string]types.AttributeValue{
			"id":        &types.AttributeValueMemberS{Value: id},
			"timestamp": &types.AttributeValueMemberN{Value: fmt.Sprintf("%d", input.Timestamp)},
		},
		UpdateExpression: aws.String("SET #data = :data, updatedAt = :updatedAt"),
		ExpressionAttributeNames: map[string]string{
			"#data": "data",
		},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":data":      dataAv,
			":updatedAt": updatedAtAv,
		},
	})

	if err != nil {
		log.Printf("DynamoDB UpdateItem error: %v", err)
		respondError(w, http.StatusInternalServerError, "Failed to update item")
		return
	}

	// Invalidate cache
	redisClient.Del(r.Context(), fmt.Sprintf("item:%s", id))

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"message": "Item updated successfully",
	})
}

func (s *Server) handleDeleteItem(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	
	var input struct {
		Timestamp int64 `json:"timestamp"`
	}

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		respondError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	_, err := dynamoClient.DeleteItem(r.Context(), &dynamodb.DeleteItemInput{
		TableName: aws.String(dynamoTableName),
		Key: map[string]types.AttributeValue{
			"id":        &types.AttributeValueMemberS{Value: id},
			"timestamp": &types.AttributeValueMemberN{Value: fmt.Sprintf("%d", input.Timestamp)},
		},
	})

	if err != nil {
		log.Printf("DynamoDB DeleteItem error: %v", err)
		respondError(w, http.StatusInternalServerError, "Failed to delete item")
		return
	}

	// Invalidate cache
	redisClient.Del(r.Context(), fmt.Sprintf("item:%s", id))

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"message": "Item deleted successfully",
	})
}

// Redis Cache Handlers
func (s *Server) handleSetCache(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Key   string      `json:"key"`
		Value interface{} `json:"value"`
		TTL   int         `json:"ttl"`
	}

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		respondError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	valueJSON, _ := json.Marshal(input.Value)
	ttl := time.Duration(input.TTL) * time.Second
	if input.TTL == 0 {
		ttl = 0
	}

	if err := redisClient.Set(r.Context(), input.Key, valueJSON, ttl).Err(); err != nil {
		respondError(w, http.StatusInternalServerError, "Failed to set cache")
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"message": "Value cached successfully",
		"key":     input.Key,
		"ttl":     input.TTL,
	})
}

func (s *Server) handleGetCache(w http.ResponseWriter, r *http.Request) {
	key := chi.URLParam(r, "key")

	val, err := redisClient.Get(r.Context(), key).Result()
	if err == redis.Nil {
		respondError(w, http.StatusNotFound, "Key not found in cache")
		return
	} else if err != nil {
		respondError(w, http.StatusInternalServerError, "Failed to get cache")
		return
	}

	var value interface{}
	json.Unmarshal([]byte(val), &value)

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"key":   key,
		"value": value,
	})
}

func (s *Server) handleDeleteCache(w http.ResponseWriter, r *http.Request) {
	key := chi.URLParam(r, "key")

	result, err := redisClient.Del(r.Context(), key).Result()
	if err != nil {
		respondError(w, http.StatusInternalServerError, "Failed to delete cache")
		return
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"message": "Key deleted successfully",
		"deleted": result > 0,
	})
}

// S3 Handlers
func (s *Server) handleUpload(w http.ResponseWriter, r *http.Request) {
	respondJSON(w, http.StatusOK, map[string]string{
		"message": "Upload endpoint - implement multipart file upload",
	})
}

func (s *Server) handleListFiles(w http.ResponseWriter, r *http.Request) {
	result, err := s3Client.ListObjectsV2(r.Context(), &s3.ListObjectsV2Input{
		Bucket:  aws.String(s3BucketData),
		MaxKeys: aws.Int32(100),
	})

	if err != nil {
		log.Printf("S3 ListObjects error: %v", err)
		respondError(w, http.StatusInternalServerError, "Failed to list files")
		return
	}

	files := make([]map[string]interface{}, 0)
	for _, obj := range result.Contents {
		files = append(files, map[string]interface{}{
			"key":          *obj.Key,
			"size":         *obj.Size,
			"lastModified": obj.LastModified,
		})
	}

	respondJSON(w, http.StatusOK, map[string]interface{}{
		"bucket": s3BucketData,
		"count":  len(files),
		"files":  files,
	})
}

// Helper functions
func respondJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(payload)
}

func respondError(w http.ResponseWriter, status int, message string) {
	respondJSON(w, status, map[string]string{"error": message})
}

func getEnvDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
