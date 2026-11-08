package httpapi

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/Shinaiders/blastgrid-arena/server/internal/auth"
	"github.com/Shinaiders/blastgrid-arena/server/internal/platform"
)

func (s *Server) registerAPIRoutes(mux *http.ServeMux) {
	mux.Handle("GET /ws", s.ws)
	mux.HandleFunc("POST /v1/auth/steam", s.handleAuthSteam)
	mux.HandleFunc("POST /v1/auth/guest", s.handleAuthGuest)
	mux.HandleFunc("POST /v1/auth/register", s.handleAuthRegister)
	mux.HandleFunc("POST /v1/auth/login", s.handleAuthLogin)
	mux.HandleFunc("GET /v1/profile", s.handleProfile)
	mux.HandleFunc("GET /v1/rankings", s.handleRankings)
	mux.HandleFunc("GET /v1/rooms", s.handleListRooms)
	mux.HandleFunc("POST /v1/rooms", s.handleCreateRoom)
	mux.HandleFunc("POST /v1/rooms/join", s.handleJoinRoom)
	mux.HandleFunc("POST /v1/matchmaking/enqueue", s.handleMatchmaking)
}

func (s *Server) handleAuthSteam(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Ticket      string `json:"ticket"`
		AppID       uint32 `json:"app_id"`
		DisplayName string `json:"display_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "bad_json"})
		return
	}
	steamID, err := platform.ValidateTicket(req.Ticket, req.AppID)
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}

	displayName := strings.TrimSpace(req.DisplayName)
	if displayName == "" {
		displayName = fmt.Sprintf("Steam_%d", steamID)
	}

	acc, token, err := s.auth.CreateGuest(displayName, time.Now())
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"access_token": token,
		"steam_id":     steamID,
		"user":         acc,
	})
}

func (s *Server) handleAuthGuest(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DisplayName string `json:"display_name"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	acc, token, err := s.auth.CreateGuest(req.DisplayName, time.Now())
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"access_token": token,
		"user":         acc,
	})
}

func (s *Server) handleAuthRegister(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email       string `json:"email"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "bad_json"})
		return
	}
	acc, token, err := s.auth.Register(req.Email, req.Password, req.DisplayName, time.Now())
	if err != nil {
		code := http.StatusBadRequest
		if err == auth.ErrEmailTaken || err == auth.ErrDisplayNameTaken {
			code = http.StatusConflict
		}
		writeJSON(w, code, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"access_token": token,
		"user":         acc,
	})
}

func (s *Server) handleAuthLogin(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "bad_json"})
		return
	}
	acc, token, err := s.auth.Login(req.Email, req.Password, time.Now())
	if err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"access_token": token,
		"user":         acc,
	})
}

func (s *Server) authenticateRequest(r *http.Request) (auth.Claims, bool) {
	hdr := strings.TrimSpace(r.Header.Get("Authorization"))
	if !strings.HasPrefix(hdr, "Bearer ") {
		return auth.Claims{}, false
	}
	tok := strings.TrimSpace(strings.TrimPrefix(hdr, "Bearer "))
	c, err := s.auth.VerifyToken(tok, time.Now())
	if err != nil {
		return auth.Claims{}, false
	}
	return c, true
}

func (s *Server) handleProfile(w http.ResponseWriter, r *http.Request) {
	claims, ok := s.authenticateRequest(r)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	acc, exists := s.auth.GetAccount(claims.UserID)
	if !exists {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "not_found"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"profile": acc})
}

func (s *Server) handleRankings(w http.ResponseWriter, _ *http.Request) {
	leaders := s.auth.TopLeaderboard(50)
	writeJSON(w, http.StatusOK, map[string]any{
		"season":      1,
		"mode":        "ffa",
		"leaderboard": leaders,
	})
}

func (s *Server) handleListRooms(w http.ResponseWriter, _ *http.Request) {
	list := s.rooms.ListPublicRooms()
	writeJSON(w, http.StatusOK, map[string]any{"rooms": list})
}

func (s *Server) handleCreateRoom(w http.ResponseWriter, r *http.Request) {
	claims, ok := s.authenticateRequest(r)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	var req struct {
		Mode       string `json:"mode"`
		MaxPlayers int    `json:"max_players"`
		Private    bool   `json:"private"`
		Platform   string `json:"platform"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	room := s.rooms.CreateRoom(claims.UserID, claims.DisplayName, req.Platform, req.Mode, req.MaxPlayers, req.Private)
	writeJSON(w, http.StatusCreated, map[string]any{"room": room})
}

func (s *Server) handleJoinRoom(w http.ResponseWriter, r *http.Request) {
	claims, ok := s.authenticateRequest(r)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	var req struct {
		RoomID   string `json:"room_id"`
		Code     string `json:"code"`
		Platform string `json:"platform"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "bad_json"})
		return
	}
	target := req.RoomID
	if target == "" {
		target = req.Code
	}
	room, part, err := s.rooms.JoinRoom(target, claims.UserID, claims.DisplayName, req.Platform)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"room":         room,
		"resume_token": part.ResumeToken,
	})
}

func (s *Server) handleMatchmaking(w http.ResponseWriter, r *http.Request) {
	claims, ok := s.authenticateRequest(r)
	if !ok {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	var req struct {
		Mode       string `json:"mode"`
		MaxPlayers int    `json:"max_players"`
		Platform   string `json:"platform"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	room, part, err := s.rooms.Matchmake(claims.UserID, claims.DisplayName, req.Platform, req.Mode, req.MaxPlayers)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"room":         room,
		"resume_token": part.ResumeToken,
	})
}
