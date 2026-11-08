package platform

import (
	"crypto/rand"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"strings"
)

const DefaultSteamAppID uint32 = 480

var (
	ErrEmptyTicket     = errors.New("steam: ticket vazio")
	ErrMalformedTicket = errors.New("steam: ticket malformado")
	ErrAppIDMismatch   = errors.New("steam: app_id divergente")
)

// ValidateTicket valida um Auth Session Ticket da Steam em formato hexadecimal.
// raw[0:8] = steamID (uint64 LE), raw[8:12] = appID (uint32 LE).
// Mínimo 16 bytes (32 caracteres hex).
func ValidateTicket(ticketHex string, expectedAppID uint32) (uint64, error) {
	ticketHex = strings.TrimSpace(ticketHex)
	if ticketHex == "" {
		return 0, ErrEmptyTicket
	}
	raw, err := hex.DecodeString(ticketHex)
	if err != nil || len(raw) < 16 {
		return 0, ErrMalformedTicket
	}

	steamID := binary.LittleEndian.Uint64(raw[0:8])
	if steamID == 0 {
		return 0, ErrMalformedTicket
	}

	appID := binary.LittleEndian.Uint32(raw[8:12])
	if expectedAppID != 0 && appID != expectedAppID {
		return 0, ErrAppIDMismatch
	}

	return steamID, nil
}

// BuildMockTicket gera um ticket hex válido de 16 bytes para testes ou desenvolvimento.
func BuildMockTicket(steamID uint64, appID uint32) string {
	var buf [16]byte
	binary.LittleEndian.PutUint64(buf[0:8], steamID)
	binary.LittleEndian.PutUint32(buf[8:12], appID)
	_, _ = rand.Read(buf[12:16])
	return hex.EncodeToString(buf[:])
}

// EvaluateAchievements avalia quais conquistas foram desbloqueadas com base nas métricas da partida.
func EvaluateAchievements(wonOnline bool, maxChain int, totalPowerups int) []string {
	var achs []string
	if wonOnline {
		achs = append(achs, "FIRST_WIN")
	}
	if maxChain >= 3 {
		achs = append(achs, "CHAIN_MASTER_3")
	}
	if totalPowerups >= 50 {
		achs = append(achs, "COLLECTOR_50")
	}
	if achs == nil {
		achs = []string{}
	}
	return achs
}
