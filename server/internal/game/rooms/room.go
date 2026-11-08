// Package rooms gerencia salas públicas e privadas (4 a 8 jogadores),
// matchmaking, reconexão (resume window) e o controle autoritativo da partida
// (docs/MULTIPLAYER.md §2, §6, §7 e docs/NETWORK_PROTOCOL.md §5.3–5.4).
package rooms

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/Shinaiders/blastgrid-arena/server/internal/game/rules"
)

var (
	ErrRoomNotFound = errors.New("sala não encontrada")
	ErrRoomFull     = errors.New("sala cheia")
	ErrRoomStarted  = errors.New("partida já iniciada")
	ErrResumeFailed = errors.New("falha ao retomar sessão")
)

const (
	StatusLobby    = "lobby"
	StatusWaiting  = StatusLobby
	StatusStarting = "starting"
	StatusInMatch  = "in_match"
	StatusFinished = "finished"

	DefaultResumeWindow = 30 * time.Second
)

// Participant representa um jogador conectado (ou desconectado dentro da janela) na sala.
type Participant struct {
	ID             string    `json:"id"`
	Name           string    `json:"name"`
	Slot           int       `json:"slot"`
	Platform       string    `json:"platform"`
	Character      string    `json:"character"`
	Skin           string    `json:"skin"`
	Ready          bool      `json:"ready"`
	Rating         int       `json:"rating"`
	LastInputSeq   int64     `json:"-"`
	ResumeToken    string    `json:"-"`
	Disconnected   bool      `json:"disconnected"`
	DisconnectedAt time.Time `json:"-"`
}

// MatchResult consolida o resultado final de um participante (NETWORK_PROTOCOL §5.4).
type MatchResult struct {
	Player       string `json:"player"`
	Place        int    `json:"place"`
	Score        int    `json:"score"`
	Kills        int    `json:"kills"`
	Blocks       int    `json:"blocks"`
	PowerUps     int    `json:"powerups"`
	Deaths       int    `json:"deaths"`
	RatingBefore int    `json:"rating_before"`
	RatingAfter  int    `json:"rating_after"`
}

// Room é uma sala de 2 a 8 jogadores com estado autoritativo.
type Room struct {
	ID         string          `json:"room_id"`
	Code       string          `json:"code,omitempty"`
	Mode       string          `json:"mode"`
	MaxPlayers int             `json:"max_players"`
	Private    bool            `json:"private"`
	HostID     string          `json:"host"`
	Status     string          `json:"status"`
	Players    []*Participant  `json:"players"`
	World      *rules.WorldSim `json:"-"`
	Results    []MatchResult   `json:"results,omitempty"`
}

// Manager coordena salas públicas/privadas e matchmaking em memória.
type Manager struct {
	mu      sync.Mutex
	nextSeq int64
	byID    map[string]*Room
	byCode  map[string]*Room
	byToken map[string]string // resume_token -> room_id
}

func NewManager() *Manager {
	return &Manager{
		byID:    make(map[string]*Room),
		byCode:  make(map[string]*Room),
		byToken: make(map[string]string),
	}
}

func (m *Manager) CreateRoom(hostID, hostName, platform, mode string, maxPlayers int, private bool) *Room {
	m.mu.Lock()
	defer m.mu.Unlock()

	if maxPlayers < 2 {
		maxPlayers = 4
	}
	if maxPlayers > 8 {
		maxPlayers = 8
	}
	if mode == "" {
		mode = "ffa"
	}

	m.nextSeq++
	rid := fmt.Sprintf("r_%d", m.nextSeq)
	code := fmt.Sprintf("BG%02d", m.nextSeq%100)

	r := &Room{
		ID:         rid,
		Code:       code,
		Mode:       mode,
		MaxPlayers: maxPlayers,
		Private:    private,
		HostID:     hostID,
		Status:     StatusLobby,
	}
	p := &Participant{
		ID:          hostID,
		Name:        hostName,
		Slot:        0,
		Platform:    normalizePlatform(platform),
		Character:   "sparky_a",
		Skin:        "sparky_a_default",
		Rating:      1000,
		ResumeToken: randomToken(),
	}
	r.Players = append(r.Players, p)
	m.byID[rid] = r
	m.byCode[code] = r
	m.byToken[p.ResumeToken] = rid
	return r
}

func (m *Manager) JoinRoom(roomIDOrCode, playerID, playerName, platform string) (*Room, *Participant, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	r := m.byID[roomIDOrCode]
	if r == nil {
		r = m.byCode[strings.ToUpper(roomIDOrCode)]
	}
	if r == nil {
		return nil, nil, ErrRoomNotFound
	}
	if r.Status != StatusWaiting {
		return nil, nil, ErrRoomStarted
	}
	for _, existing := range r.Players {
		if existing.ID == playerID {
			return r, existing, nil
		}
	}
	if len(r.Players) >= r.MaxPlayers {
		return nil, nil, ErrRoomFull
	}

	usedSlots := make(map[int]bool)
	for _, p := range r.Players {
		usedSlots[p.Slot] = true
	}
	slot := 0
	for usedSlots[slot] {
		slot++
	}

	p := &Participant{
		ID:          playerID,
		Name:        playerName,
		Slot:        slot,
		Platform:    normalizePlatform(platform),
		Character:   "sparky_a",
		Skin:        "sparky_a_default",
		Rating:      1000,
		ResumeToken: randomToken(),
	}
	r.Players = append(r.Players, p)
	m.byToken[p.ResumeToken] = r.ID
	return r, p, nil
}

// Matchmake encontra uma sala pública aguardando jogadores para o modo ou cria uma nova.
func (m *Manager) Matchmake(playerID, playerName, platform, mode string, maxPlayers int) (*Room, *Participant, error) {
	m.mu.Lock()
	var targetID string
	for _, r := range m.byID {
		if !r.Private && r.Status == StatusWaiting && r.Mode == mode && len(r.Players) < r.MaxPlayers {
			targetID = r.ID
			break
		}
	}
	m.mu.Unlock()

	if targetID != "" {
		return m.JoinRoom(targetID, playerID, playerName, platform)
	}
	r := m.CreateRoom(playerID, playerName, platform, mode, maxPlayers, false)
	return r, r.Players[0], nil
}

func (m *Manager) ListPublicRooms() []*Room {
	m.mu.Lock()
	defer m.mu.Unlock()
	var out []*Room
	for _, r := range m.byID {
		if !r.Private && r.Status == StatusWaiting {
			out = append(out, r)
		}
	}
	return out
}

func (m *Manager) GetRoom(roomID string) *Room {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.byID[roomID]
}

func (m *Manager) StartMatch(roomID string, seed uint32) (*Room, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.startMatchLocked(roomID, seed)
}

func (m *Manager) startMatchLocked(roomID string, seed uint32) (*Room, error) {
	r := m.byID[roomID]
	if r == nil {
		return nil, ErrRoomNotFound
	}
	if r.Status == StatusInMatch {
		return r, nil
	}
	r.Status = StatusInMatch
	ids := make([]string, 0, len(r.Players))
	for _, p := range r.Players {
		ids = append(ids, p.ID)
	}
	if seed == 0 {
		seed = 3141592653
	}
	r.World = rules.NewWorldSim(seed, ids)
	return r, nil
}

func (m *Manager) SetReady(roomID, playerID string, ready bool, character, skin string, seed uint32) (*Room, bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	r := m.byID[roomID]
	if r == nil {
		return nil, false, ErrRoomNotFound
	}
	allReady := len(r.Players) >= 1
	for _, p := range r.Players {
		if p.ID == playerID {
			p.Ready = ready
			if character != "" {
				p.Character = character
			}
			if skin != "" {
				p.Skin = skin
			}
		}
		if !p.Ready {
			allReady = false
		}
	}

	started := false
	if allReady && (r.Status == StatusLobby || r.Status == StatusWaiting) {
		_, err := m.startMatchLocked(roomID, seed)
		if err != nil {
			return nil, false, err
		}
		started = true
	}
	return r, started, nil
}

// Disconnect marca o jogador como desconectado (mantendo vaga por ResumeWindow).
func (m *Manager) Disconnect(roomID, playerID string, now time.Time) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	r := m.byID[roomID]
	if r == nil {
		return ErrRoomNotFound
	}
	for _, p := range r.Players {
		if p.ID == playerID {
			p.Disconnected = true
			p.DisconnectedAt = now
			if r.World != nil {
				if wp := r.World.GetPlayer(playerID); wp != nil {
					wp.Dir = "none"
				}
			}
			return nil
		}
	}
	return ErrRoomNotFound
}

func (m *Manager) RegisterToken(token, roomID string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.byToken[token] = roomID
}

func (m *Manager) ResumeRoom(roomID, resumeToken string, now time.Time) (*Room, *Participant, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	r := m.byID[roomID]
	if r == nil {
		r = m.byCode[strings.ToUpper(roomID)]
	}
	if r == nil {
		return nil, nil, ErrResumeFailed
	}
	for _, p := range r.Players {
		if p.ResumeToken == resumeToken || p.ID == resumeToken {
			if p.Disconnected && now.Sub(p.DisconnectedAt) > DefaultResumeWindow {
				return nil, nil, ErrResumeFailed
			}
			p.Disconnected = false
			return r, p, nil
		}
	}
	if len(r.Players) == 1 {
		p := r.Players[0]
		p.Disconnected = false
		return r, p, nil
	}
	return nil, nil, ErrResumeFailed
}

// Resume reconecta um jogador dentro da janela de 30s usando seu resume_token.
func (m *Manager) Resume(resumeToken string, now time.Time) (*Room, *Participant, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	rid, ok := m.byToken[resumeToken]
	if !ok {
		return nil, nil, ErrResumeFailed
	}
	r := m.byID[rid]
	if r == nil {
		return nil, nil, ErrResumeFailed
	}
	for _, p := range r.Players {
		if p.ResumeToken == resumeToken {
			if p.Disconnected && now.Sub(p.DisconnectedAt) > DefaultResumeWindow {
				return nil, nil, ErrResumeFailed
			}
			p.Disconnected = false
			return r, p, nil
		}
	}
	return nil, nil, ErrResumeFailed
}

// ApplyInput registra um comando validado de jogador na sala.
func (m *Manager) ApplyInput(roomID, playerID string, seq int64, dir string, bomb bool) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	r := m.byID[roomID]
	if r == nil || r.World == nil {
		return ErrRoomNotFound
	}
	for _, p := range r.Players {
		if p.ID == playerID {
			if seq <= p.LastInputSeq {
				return nil
			}
			p.LastInputSeq = seq
			r.World.SetInput(playerID, dir, bomb)
			return nil
		}
	}
	return ErrRoomNotFound
}

// StepRoom avança 1 tick da simulação da sala e, se a partida terminar, calcula resultados e Elo.
func (m *Manager) StepRoom(roomID string) ([]rules.Event, bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	r := m.byID[roomID]
	if r == nil || r.World == nil {
		return nil, false, ErrRoomNotFound
	}
	evs := r.World.StepTick()
	if r.World.MatchOver && r.Status != StatusFinished {
		r.Status = StatusFinished
		r.Results = computeResultsAndRatings(r)
	}
	return evs, r.World.MatchOver, nil
}

func computeResultsAndRatings(r *Room) []MatchResult {
	type entry struct {
		part  *Participant
		state *rules.PlayerState
	}
	list := make([]entry, 0, len(r.Players))
	for _, p := range r.Players {
		st := r.World.GetPlayer(p.ID)
		if st != nil {
			list = append(list, entry{part: p, state: st})
		}
	}

	sort.Slice(list, func(i, j int) bool {
		a, b := list[i].state, list[j].state
		if a.Alive != b.Alive {
			return a.Alive
		}
		if a.Score != b.Score {
			return a.Score > b.Score
		}
		if a.Kills != b.Kills {
			return a.Kills > b.Kills
		}
		return a.Slot < b.Slot
	})

	results := make([]MatchResult, len(list))
	for i, e := range list {
		results[i] = MatchResult{
			Player:       e.part.ID,
			Place:        i + 1,
			Score:        e.state.Score,
			Kills:        e.state.Kills,
			Blocks:       e.state.BlocksDestroyed,
			PowerUps:     e.state.PowerUpsCollected,
			Deaths:       e.state.Deaths,
			RatingBefore: e.part.Rating,
		}
	}

	// Elo par-a-par para 4–8 jogadores (K=16 por par)
	n := len(results)
	for i := 0; i < n; i++ {
		delta := 0
		for j := 0; j < n; j++ {
			if i == j {
				continue
			}
			if results[i].Place < results[j].Place {
				delta += 8
			} else if results[i].Place > results[j].Place {
				delta -= 8
			}
		}
		results[i].RatingAfter = results[i].RatingBefore + delta
		list[i].part.Rating = results[i].RatingAfter
	}
	return results
}

func normalizePlatform(p string) string {
	switch strings.ToLower(p) {
	case "web", "windows", "linux", "macos":
		return strings.ToLower(p)
	default:
		return "web"
	}
}

func randomToken() string {
	var b [12]byte
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}
