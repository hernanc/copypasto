export interface SignupRequest {
  email: string;
  password: string;
}

export interface LoginRequest {
  email: string;
  password: string;
}

export interface RefreshRequest {
  refreshToken: string;
}

export interface AuthResponse {
  userId: string;
  accessToken: string;
  refreshToken: string;
  encryptionSalt: string;
}

export interface TokenResponse {
  accessToken: string;
  refreshToken: string;
}

export interface ClipboardEntryResponse {
  id: string;
  ciphertext: string;
  iv: string;
  contentLength: number;
  createdAt: string;
}

export interface ClipboardListResponse {
  items: ClipboardEntryResponse[];
}

export interface HealthResponse {
  status: string;
  timestamp: string;
}
