// Package auth provê autenticação independente de plataforma (contas,
// convidados, tokens HMAC-SHA256 e sessões — docs/PROJECT_BRIEF.md §8).
package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"
)

var (
	ErrInvalidCredentials = errors.New("credenciais inválidas")
	ErrEmailTaken         = errors.New("email já cadastrado")
	ErrDisplayNameTaken   = errors.New("nome de exibição já em uso")
	ErrInvalidToken       = errors.New("token inválido ou expirado")
)

// Claims são os dados assinados dentro do access token.
type Claims struct {
	UserID      string `json:"uid"`
	DisplayName string `json:"name"`
	Kind        string `json:"kind"` // "guest" | "registered"
	ExpiresAt   int64  `json:"exp"`
}

// Account representa uma conta e seu perfil básico.
type Account struct {
	ID                string    `json:"id"`
	Email             string    `json:"email,omitempty"`
	PasswordHash      string    `json:"-"`
	Kind              string    `json:"kind"`
	DisplayName       string    `json:"display_name"`
	SelectedCharacter string    `json:"selected_character"`
	SelectedSkin      string    `json:"selected_skin"`
	Rating            int       `json:"rating"`
	MatchesPlayed     int       `json:"matches_played"`
	Wins              int       `json:"wins"`
	CreatedAt         time.Time `json:"created_at"`
}

// Service gerencia contas, convidados e emissão/verificação de tokens.
type Service struct {
	mu          sync.RWMutex
	secret      []byte
	tokenTTL    time.Duration
	nextSeq     int64
	byID        map[string]*Account
	byEmail     map[string]string
	byNameLower map[string]string
}

func NewService(secret string, tokenTTL time.Duration) *Service {
	if secret == "" {
		secret = "dev-secret-blastgrid-arena-key"
	}
	if tokenTTL <= 0 {
		tokenTTL = 24 * time.Hour
	}
	return &Service{
		secret:      []byte(secret),
		tokenTTL:    tokenTTL,
		byID:        make(map[string]*Account),
		byEmail:     make(map[string]string),
		byNameLower: make(map[string]string),
	}
}

func (s *Service) CreateGuest(displayName string, now time.Time) (*Account, string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.nextSeq++
	uid := fmt.Sprintf("u_%d", s.nextSeq)
	name := strings.TrimSpace(displayName)
	if len(name) < 3 || len(name) > 20 {
		name = fmt.Sprintf("Guest_%d", s.nextSeq)
	}
	if _, exists := s.byNameLower[strings.ToLower(name)]; exists {
		name = fmt.Sprintf("%s_%d", name[:min(len(name), 14)], s.nextSeq)
	}

	acc := &Account{
		ID:                uid,
		Kind:              "guest",
		DisplayName:       name,
		SelectedCharacter: "sparky_a",
		SelectedSkin:      "sparky_a_default",
		Rating:            1000,
		CreatedAt:         now.UTC(),
	}
	s.byID[uid] = acc
	s.byNameLower[strings.ToLower(name)] = uid

	tok, err := s.issueToken(acc, now)
	return acc, tok, err
}

func (s *Service) Register(email, password, displayName string, now time.Time) (*Account, string, error) {
	emailNorm := strings.ToLower(strings.TrimSpace(email))
	name := strings.TrimSpace(displayName)
	if len(emailNorm) < 3 || !strings.Contains(emailNorm, "@") || len(password) < 6 || len(name) < 3 || len(name) > 20 {
		return nil, "", ErrInvalidCredentials
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	if _, exists := s.byEmail[emailNorm]; exists {
		return nil, "", ErrEmailTaken
	}
	if _, exists := s.byNameLower[strings.ToLower(name)]; exists {
		return nil, "", ErrDisplayNameTaken
	}

	s.nextSeq++
	uid := fmt.Sprintf("u_%d", s.nextSeq)
	acc := &Account{
		ID:                uid,
		Email:             emailNorm,
		PasswordHash:      hashPassword(password, s.secret),
		Kind:              "registered",
		DisplayName:       name,
		SelectedCharacter: "sparky_a",
		SelectedSkin:      "sparky_a_default",
		Rating:            1000,
		CreatedAt:         now.UTC(),
	}
	s.byID[uid] = acc
	s.byEmail[emailNorm] = uid
	s.byNameLower[strings.ToLower(name)] = uid

	tok, err := s.issueToken(acc, now)
	return acc, tok, err
}

func (s *Service) Login(email, password string, now time.Time) (*Account, string, error) {
	emailNorm := strings.ToLower(strings.TrimSpace(email))
	s.mu.RLock()
	uid, ok := s.byEmail[emailNorm]
	var acc *Account
	if ok {
		acc = s.byID[uid]
	}
	s.mu.RUnlock()

	if acc == nil || !verifyPassword(password, acc.PasswordHash, s.secret) {
		return nil, "", ErrInvalidCredentials
	}
	tok, err := s.issueToken(acc, now)
	return acc, tok, err
}

func (s *Service) GetAccount(userID string) (*Account, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	acc, ok := s.byID[userID]
	if !ok {
		return nil, false
	}
	cp := *acc
	return &cp, true
}

func (s *Service) RecordMatchOutcome(userID string, ratingDelta int, won bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if acc, ok := s.byID[userID]; ok {
		acc.MatchesPlayed++
		if won {
			acc.Wins++
		}
		acc.Rating += ratingDelta
		if acc.Rating < 100 {
			acc.Rating = 100
		}
	}
}

func (s *Service) TopLeaderboard(limit int) []Account {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Account, 0, len(s.byID))
	for _, a := range s.byID {
		out = append(out, *a)
	}
	// Ordena por Rating DESC, Wins DESC, ID ASC
	for i := 0; i < len(out); i++ {
		for j := i + 1; j < len(out); j++ {
			if out[j].Rating > out[i].Rating || (out[j].Rating == out[i].Rating && out[j].Wins > out[i].Wins) {
				out[i], out[j] = out[j], out[i]
			}
		}
	}
	if limit > 0 && len(out) > limit {
		out = out[:limit]
	}
	return out
}

func (s *Service) issueToken(acc *Account, now time.Time) (string, error) {
	claims := Claims{
		UserID:      acc.ID,
		DisplayName: acc.DisplayName,
		Kind:        acc.Kind,
		ExpiresAt:   now.Add(s.tokenTTL).Unix(),
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	b64 := base64.RawURLEncoding.EncodeToString(payload)
	sig := signHMAC([]byte(b64), s.secret)
	return b64 + "." + base64.RawURLEncoding.EncodeToString(sig), nil
}

func (s *Service) VerifyToken(token string, now time.Time) (Claims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 2 {
		return Claims{}, ErrInvalidToken
	}
	wantSig := signHMAC([]byte(parts[0]), s.secret)
	gotSig, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil || subtle.ConstantTimeCompare(wantSig, gotSig) != 1 {
		return Claims{}, ErrInvalidToken
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return Claims{}, ErrInvalidToken
	}
	var c Claims
	if err := json.Unmarshal(payload, &c); err != nil {
		return Claims{}, ErrInvalidToken
	}
	if now.Unix() > c.ExpiresAt {
		return Claims{}, ErrInvalidToken
	}
	return c, nil
}

func signHMAC(msg, key []byte) []byte {
	mac := hmac.New(sha256.New, key)
	mac.Write(msg)
	return mac.Sum(nil)
}

func hashPassword(password string, pepper []byte) string {
	var salt [16]byte
	_, _ = rand.Read(salt[:])
	mac := hmac.New(sha256.New, pepper)
	mac.Write(salt[:])
	mac.Write([]byte(password))
	return hex.EncodeToString(salt[:]) + ":" + hex.EncodeToString(mac.Sum(nil))
}

func verifyPassword(password, stored string, pepper []byte) bool {
	parts := strings.Split(stored, ":")
	if len(parts) != 2 {
		return false
	}
	salt, err1 := hex.DecodeString(parts[0])
	want, err2 := hex.DecodeString(parts[1])
	if err1 != nil || err2 != nil {
		return false
	}
	mac := hmac.New(sha256.New, pepper)
	mac.Write(salt)
	mac.Write([]byte(password))
	return subtle.ConstantTimeCompare(mac.Sum(nil), want) == 1
}
