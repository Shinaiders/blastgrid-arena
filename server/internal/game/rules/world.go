package rules

import "sort"

const (
	TileSize        = 1000
	HalfTile        = 500
	CornerTolerance = 400

	BaseSpeed = 200
	SpeedStep = 25
	MaxSpeed  = 350

	BaseBombs = 1
	MaxBombs  = 8

	BaseRange = 2
	MaxRange  = 8

	DefaultFuseTicks     = 50
	DefaultFlameTicks    = 10
	DefaultTickRate      = 20
	DefaultDurationTicks = 3600
	ShieldDurationTicks  = 120
	DropChancePct        = 30

	ScoreKill     = 100
	ScoreBlock    = 10
	ScorePowerUp  = 5
	ScoreWin      = 300
	ScoreSelfKill = -50
)

const (
	KindRangeUp = "range_up"
	KindBombUp  = "bomb_up"
	KindSpeedUp = "speed_up"
	KindShield  = "shield"
)

// PlayerState representa um jogador na simulação autoritativa.
type PlayerState struct {
	ID                string `json:"id"`
	Slot              int    `json:"slot"`
	X                 int    `json:"x"`
	Y                 int    `json:"y"`
	Dir               string `json:"dir"`
	Alive             bool   `json:"alive"`
	Disconnected      bool   `json:"-"`
	Speed             int    `json:"speed"`
	MaxBombs          int    `json:"bombs"`
	BombRange         int    `json:"range"`
	ShieldTicks       int    `json:"shield"`
	InvulnerableTicks int    `json:"-"`

	Score             int `json:"-"`
	Kills             int `json:"-"`
	Deaths            int `json:"-"`
	BlocksDestroyed   int `json:"-"`
	PowerUpsCollected int `json:"-"`
}

func NewPlayerState(id string, slot int, spawn CellCoord) *PlayerState {
	return &PlayerState{
		ID:        id,
		Slot:      slot,
		X:         spawn.X*TileSize + HalfTile,
		Y:         spawn.Y*TileSize + HalfTile,
		Dir:       "none",
		Alive:     true,
		Speed:     BaseSpeed,
		MaxBombs:  BaseBombs,
		BombRange: BaseRange,
	}
}

func (p *PlayerState) CellX() int { return p.X / TileSize }
func (p *PlayerState) CellY() int { return p.Y / TileSize }

func (p *PlayerState) OverlapsCell(cx, cy int) bool {
	centerX := cx*TileSize + HalfTile
	centerY := cy*TileSize + HalfTile
	return absInt(p.X-centerX) < TileSize && absInt(p.Y-centerY) < TileSize
}

// BombState representa uma bomba plantada na arena.
type BombState struct {
	ID             int             `json:"id"`
	OwnerID        string          `json:"owner"`
	CX             int             `json:"cx"`
	CY             int             `json:"cy"`
	Fuse           int             `json:"fuse"`
	Range          int             `json:"range"`
	PassThroughIDs map[string]bool `json:"-"`
}

func (b *BombState) BlocksPlayer(playerID string) bool {
	return !b.PassThroughIDs[playerID]
}

func (b *BombState) UpdatePassThrough(players []*PlayerState) {
	if len(b.PassThroughIDs) == 0 {
		return
	}
	for pid := range b.PassThroughIDs {
		still := false
		for _, p := range players {
			if p.ID == pid && p.Alive && p.OverlapsCell(b.CX, b.CY) {
				still = true
				break
			}
		}
		if !still {
			delete(b.PassThroughIDs, pid)
		}
	}
}

// PowerUpItem representa um power-up exposto no chão.
type PowerUpItem struct {
	CX   int    `json:"cx"`
	CY   int    `json:"cy"`
	Kind string `json:"kind"`
}

type flameCell struct {
	CX        int
	CY        int
	OwnerID   string
	TicksLeft int
}

type playerInput struct {
	Dir  string
	Bomb bool
}

// Event representa um evento ocorrido durante o tick (NETWORK_PROTOCOL §5.4).
type Event map[string]any

// WorldSim é o motor autoritativo de simulação da partida.
type WorldSim struct {
	Seed          uint32
	Tick          int
	TickRate      int
	DurationTicks int
	FuseTicks     int
	FlameTicks    int

	RNG        *PRNG
	Grid       *Grid
	Players    []*PlayerState
	Bombs      []*BombState
	NextBombID int

	PowerUps      map[int]PowerUpItem
	Flames        map[int]*flameCell
	PendingInputs map[string]playerInput

	MatchOver bool
	EndReason string
	WinnerID  string
}

// NewWorldSim cria uma nova simulação determinística para os jogadores dados.
func NewWorldSim(seed uint32, playerIDs []string) *WorldSim {
	w := &WorldSim{
		Seed:          seed,
		TickRate:      DefaultTickRate,
		DurationTicks: DefaultDurationTicks,
		FuseTicks:     DefaultFuseTicks,
		FlameTicks:    DefaultFlameTicks,
		RNG:           NewPRNG(seed ^ 0x9E3779B9),
		Grid:          GenerateGrid(seed, len(playerIDs)),
		NextBombID:    1,
		PowerUps:      make(map[int]PowerUpItem),
		Flames:        make(map[int]*flameCell),
		PendingInputs: make(map[string]playerInput),
	}
	for i, id := range playerIDs {
		sp := Spawns[i%len(Spawns)]
		w.Players = append(w.Players, NewPlayerState(id, i, sp))
	}
	return w
}

func (w *WorldSim) GetPlayer(id string) *PlayerState {
	for _, p := range w.Players {
		if p.ID == id {
			return p
		}
	}
	return nil
}

func IsValidDir(d string) bool {
	switch d {
	case "none", "up", "down", "left", "right":
		return true
	default:
		return false
	}
}

func dirVector(d string) (int, int) {
	switch d {
	case "up":
		return 0, -1
	case "down":
		return 0, 1
	case "left":
		return -1, 0
	case "right":
		return 1, 0
	default:
		return 0, 0
	}
}

// SetInput registra a intenção de entrada do jogador para o próximo tick.
func (w *WorldSim) SetInput(playerID, dir string, placeBomb bool) {
	if !IsValidDir(dir) {
		dir = "none"
	}
	prev := w.PendingInputs[playerID]
	w.PendingInputs[playerID] = playerInput{
		Dir:  dir,
		Bomb: prev.Bomb || placeBomb,
	}
}

func (w *WorldSim) GetBombAt(cx, cy int) *BombState {
	for _, b := range w.Bombs {
		if b.CX == cx && b.CY == cy {
			return b
		}
	}
	return nil
}

func (w *WorldSim) CountPlayerBombs(playerID string) int {
	c := 0
	for _, b := range w.Bombs {
		if b.OwnerID == playerID {
			c++
		}
	}
	return c
}

func (w *WorldSim) IsCellBlockedByBomb(cx, cy int, playerID string) bool {
	b := w.GetBombAt(cx, cy)
	if b == nil {
		return false
	}
	return b.BlocksPlayer(playerID)
}

func (w *WorldSim) PlacePowerUp(cx, cy int, kind string) {
	w.PowerUps[cy*w.Grid.Cols+cx] = PowerUpItem{CX: cx, CY: cy, Kind: kind}
}

// StepPlayer executa um passo de movimentação para p sobre w.Grid.
func StepPlayer(p *PlayerState, g *Grid, blockedFn func(cx, cy int, playerID string) bool) {
	if !p.Alive || p.Disconnected {
		return
	}
	dx, dy := dirVector(p.Dir)
	if dx == 0 && dy == 0 {
		return
	}
	budget := p.Speed
	if budget <= 0 {
		return
	}
	if dx != 0 {
		moveHorizontal(p, g, dx, budget, blockedFn)
	} else {
		moveVertical(p, g, dy, budget, blockedFn)
	}
}

func canEnter(g *Grid, cx, cy int, playerID string, blockedFn func(cx, cy int, playerID string) bool) bool {
	if g.IsSolidTile(cx, cy) {
		return false
	}
	if blockedFn != nil && blockedFn(cx, cy, playerID) {
		return false
	}
	return true
}

func moveHorizontal(p *PlayerState, g *Grid, dx, budget int, blockedFn func(cx, cy int, playerID string) bool) {
	cx := p.X / TileSize
	cy := p.Y / TileSize
	centerX := cx*TileSize + HalfTile
	centerY := cy*TileSize + HalfTile

	targetY := -1
	canAdvanceCurrent := ((centerX-p.X)*dx > 0) || canEnter(g, cx+dx, cy, p.ID, blockedFn)
	if canAdvanceCurrent {
		targetY = centerY
	} else {
		distTop := p.Y - (cy * TileSize)
		distBottom := ((cy + 1) * TileSize) - p.Y
		if distTop <= CornerTolerance && canEnter(g, cx, cy-1, p.ID, blockedFn) && canEnter(g, cx+dx, cy-1, p.ID, blockedFn) {
			targetY = (cy-1)*TileSize + HalfTile
		} else if distBottom <= CornerTolerance && canEnter(g, cx, cy+1, p.ID, blockedFn) && canEnter(g, cx+dx, cy+1, p.ID, blockedFn) {
			targetY = (cy+1)*TileSize + HalfTile
		}
	}

	if targetY < 0 {
		return
	}

	if p.Y != targetY {
		diffY := targetY - p.Y
		stepY := minInt(absInt(diffY), budget)
		if diffY > 0 {
			p.Y += stepY
		} else {
			p.Y -= stepY
		}
		budget -= stepY
	}

	if p.Y != targetY || budget <= 0 {
		return
	}

	rowY := p.Y / TileSize
	for budget > 0 {
		curCX := p.X / TileSize
		curCenterX := curCX*TileSize + HalfTile
		if (curCenterX-p.X)*dx > 0 {
			dist := absInt(curCenterX - p.X)
			mv := minInt(dist, budget)
			p.X += dx * mv
			budget -= mv
		} else {
			if !canEnter(g, curCX+dx, rowY, p.ID, blockedFn) {
				break
			}
			nextCenterX := (curCX+dx)*TileSize + HalfTile
			dist := absInt(nextCenterX - p.X)
			mv := minInt(dist, budget)
			p.X += dx * mv
			budget -= mv
		}
	}
}

func moveVertical(p *PlayerState, g *Grid, dy, budget int, blockedFn func(cx, cy int, playerID string) bool) {
	cx := p.X / TileSize
	cy := p.Y / TileSize
	centerX := cx*TileSize + HalfTile
	centerY := cy*TileSize + HalfTile

	targetX := -1
	canAdvanceCurrent := ((centerY-p.Y)*dy > 0) || canEnter(g, cx, cy+dy, p.ID, blockedFn)
	if canAdvanceCurrent {
		targetX = centerX
	} else {
		distLeft := p.X - (cx * TileSize)
		distRight := ((cx + 1) * TileSize) - p.X
		if distLeft <= CornerTolerance && canEnter(g, cx-1, cy, p.ID, blockedFn) && canEnter(g, cx-1, cy+dy, p.ID, blockedFn) {
			targetX = (cx-1)*TileSize + HalfTile
		} else if distRight <= CornerTolerance && canEnter(g, cx+1, cy, p.ID, blockedFn) && canEnter(g, cx+1, cy+dy, p.ID, blockedFn) {
			targetX = (cx+1)*TileSize + HalfTile
		}
	}

	if targetX < 0 {
		return
	}

	if p.X != targetX {
		diffX := targetX - p.X
		stepX := minInt(absInt(diffX), budget)
		if diffX > 0 {
			p.X += stepX
		} else {
			p.X -= stepX
		}
		budget -= stepX
	}

	if p.X != targetX || budget <= 0 {
		return
	}

	colX := p.X / TileSize
	for budget > 0 {
		curCY := p.Y / TileSize
		curCenterY := curCY*TileSize + HalfTile
		if (curCenterY-p.Y)*dy > 0 {
			dist := absInt(curCenterY - p.Y)
			mv := minInt(dist, budget)
			p.Y += dy * mv
			budget -= mv
		} else {
			if !canEnter(g, colX, curCY+dy, p.ID, blockedFn) {
				break
			}
			nextCenterY := (curCY+dy)*TileSize + HalfTile
			dist := absInt(nextCenterY - p.Y)
			mv := minInt(dist, budget)
			p.Y += dy * mv
			budget -= mv
		}
	}
}

// ApplyPowerUp aplica o efeito do power-up ao jogador respeitando os limites do GDD §7.
func ApplyPowerUp(p *PlayerState, kind string) {
	switch kind {
	case KindRangeUp:
		p.BombRange = minInt(p.BombRange+1, MaxRange)
	case KindBombUp:
		p.MaxBombs = minInt(p.MaxBombs+1, MaxBombs)
	case KindSpeedUp:
		p.Speed = minInt(p.Speed+SpeedValues(), MaxSpeed)
	case KindShield:
		p.ShieldTicks = ShieldDurationTicks
	}
}

func SpeedValues() int { return SpeedStep }

func RollDrop(rng *PRNG) string {
	if int(rng.NextBound(100)) >= DropChancePct {
		return ""
	}
	w := int(rng.NextBound(100))
	if w < 35 {
		return KindRangeUp
	}
	if w < 70 {
		return KindBombUp
	}
	if w < 90 {
		return KindSpeedUp
	}
	return KindShield
}

// StepTick avança 1 tick completo da partida seguindo a ordem de ARCHITECTURE.md §5.
func (w *WorldSim) StepTick() []Event {
	var events []Event
	if w.MatchOver {
		return events
	}

	w.Tick++

	for _, p := range w.Players {
		if p.ShieldTicks > 0 {
			p.ShieldTicks--
		}
		if p.InvulnerableTicks > 0 {
			p.InvulnerableTicks--
		}
	}

	for k, f := range w.Flames {
		f.TicksLeft--
		if f.TicksLeft <= 0 {
			delete(w.Flames, k)
		}
	}

	// 1. Entradas & 2. Movimento
	var bombRequests []*PlayerState
	for _, p := range w.Players {
		if !p.Alive || p.Disconnected {
			continue
		}
		if inp, ok := w.PendingInputs[p.ID]; ok {
			p.Dir = inp.Dir
			if inp.Bomb {
				bombRequests = append(bombRequests, p)
			}
		}
		StepPlayer(p, w.Grid, w.IsCellBlockedByBomb)
	}
	clear(w.PendingInputs)

	for _, b := range w.Bombs {
		b.UpdatePassThrough(w.Players)
	}

	// 4. Pavios de bombas existentes
	var detonateQueue []*BombState
	queuedIDs := make(map[int]bool)
	for _, b := range w.Bombs {
		b.Fuse--
		if b.Fuse <= 0 {
			detonateQueue = append(detonateQueue, b)
			queuedIDs[b.ID] = true
		}
	}

	// 3. Colocação de bombas novas
	for _, p := range bombRequests {
		cx, cy := p.CellX(), p.CellY()
		if w.Grid.GetTile(cx, cy) != TileEmpty {
			continue
		}
		if w.GetBombAt(cx, cy) != nil {
			continue
		}
		if w.CountPlayerBombs(p.ID) >= p.MaxBombs {
			continue
		}
		nb := &BombState{
			ID:             w.NextBombID,
			OwnerID:        p.ID,
			CX:             cx,
			CY:             cy,
			Fuse:           w.FuseTicks,
			Range:          p.BombRange,
			PassThroughIDs: make(map[string]bool),
		}
		w.NextBombID++
		for _, other := range w.Players {
			if other.Alive && other.OverlapsCell(cx, cy) {
				nb.PassThroughIDs[other.ID] = true
			}
		}
		w.Bombs = append(w.Bombs, nb)
		events = append(events, Event{
			"k":     "bomb_placed",
			"id":    nb.ID,
			"owner": p.ID,
			"cx":    cx,
			"cy":    cy,
		})
	}

	// 5. Explosões e reação em cadeia (FIFO determinístico)
	type blockHit struct {
		CX      int
		CY      int
		OwnerID string
	}
	destroyedBlocks := make(map[int]blockHit)
	tickFlameCells := make(map[int]blockHit)
	detonatedIDs := make(map[int]bool)

	dirs := [][2]int{{0, -1}, {0, 1}, {-1, 0}, {1, 0}}
	for qIdx := 0; qIdx < len(detonateQueue); qIdx++ {
		b := detonateQueue[qIdx]
		detonatedIDs[b.ID] = true

		blastCells := [][2]int{{b.CX, b.CY}}
		centerKey := b.CY*w.Grid.Cols + b.CX
		if _, exists := tickFlameCells[centerKey]; !exists {
			tickFlameCells[centerKey] = blockHit{CX: b.CX, CY: b.CY, OwnerID: b.OwnerID}
		}
		w.Flames[centerKey] = &flameCell{CX: b.CX, CY: b.CY, OwnerID: b.OwnerID, TicksLeft: w.FlameTicks}

		var newlyTriggered []*BombState
		for _, d := range dirs {
			for step := 1; step <= b.Range; step++ {
				nx := b.CX + d[0]*step
				ny := b.CY + d[1]*step
				t := w.Grid.GetTile(nx, ny)
				if t == TileWall {
					break
				}
				key := ny*w.Grid.Cols + nx
				blastCells = append(blastCells, [2]int{nx, ny})
				if _, exists := tickFlameCells[key]; !exists {
					tickFlameCells[key] = blockHit{CX: nx, CY: ny, OwnerID: b.OwnerID}
				}
				w.Flames[key] = &flameCell{CX: nx, CY: ny, OwnerID: b.OwnerID, TicksLeft: w.FlameTicks}

				if t == TileBlock {
					if _, exists := destroyedBlocks[key]; !exists {
						destroyedBlocks[key] = blockHit{CX: nx, CY: ny, OwnerID: b.OwnerID}
					}
					break
				}

				if otherBomb := w.GetBombAt(nx, ny); otherBomb != nil && !queuedIDs[otherBomb.ID] {
					otherBomb.Fuse = 0
					queuedIDs[otherBomb.ID] = true
					newlyTriggered = append(newlyTriggered, otherBomb)
				}
			}
		}

		sort.Slice(newlyTriggered, func(i, j int) bool { return newlyTriggered[i].ID < newlyTriggered[j].ID })
		detonateQueue = append(detonateQueue, newlyTriggered...)

		events = append(events, Event{
			"k":       "explosion",
			"bomb_id": b.ID,
			"owner":   b.OwnerID,
			"cells":   blastCells,
		})
	}

	if len(detonatedIDs) > 0 {
		remaining := make([]*BombState, 0, len(w.Bombs))
		for _, b := range w.Bombs {
			if !detonatedIDs[b.ID] {
				remaining = append(remaining, b)
			}
		}
		w.Bombs = remaining
	}

	// 6. Destruição de power-ups já expostos + blocos e drops
	var exposedKeys []int
	for k := range tickFlameCells {
		exposedKeys = append(exposedKeys, k)
	}
	sort.Ints(exposedKeys)
	for _, key := range exposedKeys {
		if pu, ok := w.PowerUps[key]; ok {
			delete(w.PowerUps, key)
			events = append(events, Event{
				"k":  "powerup_destroyed",
				"cx": pu.CX,
				"cy": pu.CY,
			})
		}
	}

	var blockKeys []int
	for k := range destroyedBlocks {
		blockKeys = append(blockKeys, k)
	}
	sort.Ints(blockKeys)
	for _, key := range blockKeys {
		info := destroyedBlocks[key]
		w.Grid.SetTile(info.CX, info.CY, TileEmpty)
		if owner := w.GetPlayer(info.OwnerID); owner != nil {
			owner.BlocksDestroyed++
			owner.Score += ScoreBlock
		}
		dropKind := RollDrop(w.RNG)
		var dropVal any
		if dropKind != "" {
			w.PlacePowerUp(info.CX, info.CY, dropKind)
			dropVal = dropKind
		}
		events = append(events, Event{
			"k":    "block_destroyed",
			"cx":   info.CX,
			"cy":   info.CY,
			"drop": dropVal,
		})
	}

	// 7. Coleta de power-ups
	for _, p := range w.Players {
		if !p.Alive {
			continue
		}
		cx, cy := p.CellX(), p.CellY()
		key := cy*w.Grid.Cols + cx
		if pu, ok := w.PowerUps[key]; ok {
			delete(w.PowerUps, key)
			ApplyPowerUp(p, pu.Kind)
			p.PowerUpsCollected++
			p.Score += ScorePowerUp
			events = append(events, Event{
				"k":      "powerup_collected",
				"player": p.ID,
				"cx":     cx,
				"cy":     cy,
				"kind":   pu.Kind,
			})
		}
	}

	// 8. Eliminações
	for _, p := range w.Players {
		if !p.Alive {
			continue
		}
		key := p.CellY()*w.Grid.Cols + p.CellX()
		fl, ok := w.Flames[key]
		if !ok {
			continue
		}
		if p.InvulnerableTicks > 0 {
			continue
		}
		if p.ShieldTicks > 0 {
			p.ShieldTicks = 0
			p.InvulnerableTicks = w.FlameTicks
			events = append(events, Event{
				"k":      "shield_broken",
				"player": p.ID,
			})
			continue
		}

		p.Alive = false
		p.Deaths++
		if fl.OwnerID == p.ID {
			p.Score += ScoreSelfKill
		} else if killer := w.GetPlayer(fl.OwnerID); killer != nil {
			killer.Kills++
			killer.Score += ScoreKill
		}
		events = append(events, Event{
			"k":      "player_eliminated",
			"player": p.ID,
			"by":     fl.OwnerID,
		})
	}

	// 9. Condição de vitória
	w.checkVictory()

	return events
}

func (w *WorldSim) checkVictory() {
	if w.MatchOver {
		return
	}
	var alive []*PlayerState
	for _, p := range w.Players {
		if p.Alive && !p.Disconnected {
			alive = append(alive, p)
		}
	}

	if len(w.Players) > 1 && len(alive) <= 1 {
		w.MatchOver = true
		if len(alive) == 1 {
			w.WinnerID = alive[0].ID
			w.EndReason = "last_alive"
			alive[0].Score += ScoreWin
		} else {
			w.WinnerID = ""
			w.EndReason = "draw"
		}
		return
	}

	if w.Tick >= w.DurationTicks {
		w.MatchOver = true
		if len(alive) == 0 {
			w.WinnerID = ""
			w.EndReason = "draw"
			return
		}
		bestScore := -999999999
		var bestPlayers []*PlayerState
		for _, p := range alive {
			if p.Score > bestScore {
				bestScore = p.Score
				bestPlayers = []*PlayerState{p}
			} else if p.Score == bestScore {
				bestPlayers = append(bestPlayers, p)
			}
		}
		if len(bestPlayers) == 1 {
			w.WinnerID = bestPlayers[0].ID
			w.EndReason = "time_up"
			bestPlayers[0].Score += ScoreWin
		} else {
			w.WinnerID = ""
			w.EndReason = "draw"
		}
	}
}

func absInt(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}
