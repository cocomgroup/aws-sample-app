// src/lib/api.ts
// API client for communicating with Go backend

const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:8080/api';

export interface Item {
	id: string;
	timestamp: number;
	data: Record<string, any>;
	createdAt: string;
	updatedAt?: string;
}

export interface CacheItem {
	key: string;
	value: any;
	ttl?: number;
}

export interface ApiResponse<T> {
	data?: T;
	error?: string;
	message?: string;
}

class ApiClient {
	private baseUrl: string;

	constructor(baseUrl: string = API_URL) {
		this.baseUrl = baseUrl;
	}

	private async request<T>(
		endpoint: string,
		options: RequestInit = {}
	): Promise<ApiResponse<T>> {
		try {
			const response = await fetch(`${this.baseUrl}${endpoint}`, {
				...options,
				headers: {
					'Content-Type': 'application/json',
					...options.headers
				}
			});

			const data = await response.json();

			if (!response.ok) {
				return {
					error: data.error || 'An error occurred'
				};
			}

			return { data };
		} catch (error) {
			console.error('API request failed:', error);
			return {
				error: error instanceof Error ? error.message : 'Network error'
			};
		}
	}

	// ==========================================
	// Item Management
	// ==========================================

	async createItem(id: string, data: Record<string, any>): Promise<ApiResponse<Item>> {
		return this.request<Item>('/items', {
			method: 'POST',
			body: JSON.stringify({ id, data })
		});
	}

	async getItem(id: string): Promise<ApiResponse<{ source: string; item: Item }>> {
		return this.request<{ source: string; item: Item }>(`/items/${id}`);
	}

	async listItems(): Promise<ApiResponse<{ count: number; items: Item[] }>> {
		return this.request<{ count: number; items: Item[] }>('/items');
	}

	async updateItem(
		id: string,
		timestamp: number,
		data: Record<string, any>
	): Promise<ApiResponse<{ message: string }>> {
		return this.request<{ message: string }>(`/items/${id}`, {
			method: 'PUT',
			body: JSON.stringify({ timestamp, data })
		});
	}

	async deleteItem(
		id: string,
		timestamp: number
	): Promise<ApiResponse<{ message: string }>> {
		return this.request<{ message: string }>(`/items/${id}`, {
			method: 'DELETE',
			body: JSON.stringify({ timestamp })
		});
	}

	// ==========================================
	// Cache Management
	// ==========================================

	async setCache(key: string, value: any, ttl?: number): Promise<ApiResponse<CacheItem>> {
		return this.request<CacheItem>('/cache', {
			method: 'POST',
			body: JSON.stringify({ key, value, ttl: ttl || 0 })
		});
	}

	async getCache(key: string): Promise<ApiResponse<CacheItem>> {
		return this.request<CacheItem>(`/cache/${key}`);
	}

	async deleteCache(key: string): Promise<ApiResponse<{ message: string; deleted: boolean }>> {
		return this.request<{ message: string; deleted: boolean }>(`/cache/${key}`, {
			method: 'DELETE'
		});
	}

	// ==========================================
	// File Management
	// ==========================================

	async listFiles(): Promise<
		ApiResponse<{ bucket: string; count: number; files: any[] }>
	> {
		return this.request<{ bucket: string; count: number; files: any[] }>('/files');
	}

	async uploadFile(file: File): Promise<ApiResponse<{ message: string }>> {
		const formData = new FormData();
		formData.append('file', file);

		try {
			const response = await fetch(`${this.baseUrl}/upload`, {
				method: 'POST',
				body: formData
			});

			const data = await response.json();

			if (!response.ok) {
				return { error: data.error || 'Upload failed' };
			}

			return { data };
		} catch (error) {
			return {
				error: error instanceof Error ? error.message : 'Upload failed'
			};
		}
	}

	// ==========================================
	// Health Check
	// ==========================================

	async checkHealth(): Promise<
		ApiResponse<{
			status: string;
			timestamp: string;
			services: Record<string, string>;
		}>
	> {
		// Health check is at root, not under /api
		try {
			const response = await fetch(`${this.baseUrl.replace('/api', '')}/health`);
			const data = await response.json();

			if (!response.ok) {
				return { error: 'Health check failed' };
			}

			return { data };
		} catch (error) {
			return {
				error: error instanceof Error ? error.message : 'Health check failed'
			};
		}
	}
}

// Export singleton instance
export const api = new ApiClient();

// Export class for custom instances
export default ApiClient;
