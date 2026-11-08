package auth_test

import (
	"testing"
	"time"

	"github.com/Shinaiders/blastgrid-arena/server/internal/auth"
)

func TestGuestAndRegisteredAuthFlow(t *testing.T) {
	now := time.Now()
	svc := auth.NewService("test-secret", time.Hour)

	guest, gTok, err := svc.CreateGuest("SparkPlayer", now)
	if err != nil {
		t.Fatalf("CreateGuest: %v", err)
	}
	claims, err := svc.VerifyToken(gTok, now)
	if err != nil || claims.UserID != guest.ID || claims.Kind != "guest" {
		t.Fatalf("VerifyToken guest falhou: %+v, err=%v", claims, err)
	}

	// Token expirado deve falhar
	if _, err := svc.VerifyToken(gTok, now.Add(2*time.Hour)); err == nil {
		t.Fatal("token expirado deveria ser rejeitado")
	}

	// Registro e Login
	acc, rTok, err := svc.Register("Volt@Example.com", "secret123", "VoltPro", now)
	if err != nil {
		t.Fatalf("Register: %v", err)
	}
	if acc.Kind != "registered" {
		t.Fatalf("esperava registered, obteve %s", acc.Kind)
	}
	if _, err := svc.VerifyToken(rTok, now); err != nil {
		t.Fatalf("VerifyToken registered: %v", err)
	}

	// Email duplicado (case-insensitive)
	if _, _, err := svc.Register("volt@example.com", "other123", "OtherName", now); err != auth.ErrEmailTaken {
		t.Fatalf("esperava ErrEmailTaken, obteve %v", err)
	}

	// Login válido e inválido
	if _, _, err := svc.Login("VOLT@example.com", "secret123", now); err != nil {
		t.Fatalf("Login válido falhou: %v", err)
	}
	if _, _, err := svc.Login("volt@example.com", "errada", now); err != auth.ErrInvalidCredentials {
		t.Fatalf("Login com senha incorreta deveria falhar: %v", err)
	}
}
