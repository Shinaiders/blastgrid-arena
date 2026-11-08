package persistence

import (
	"context"
	"sort"
	"time"

	"github.com/jackc/pgx/v5"
)

// MatchPlayerRecord representa a linha de um participante ao persistir uma partida (DATABASE.md §3, §5).
type MatchPlayerRecord struct {
	Slot         int16
	UserID       *int64
	Place        int16
	Score        int32
	Kills        int16
	Deaths       int16
	Blocks       int16
	PowerUps     int16
	Platform     string
	Disconnected bool
	RatingBefore *int32
	RatingAfter  *int32
}

// MatchRecord reúne os metadados e participantes de uma partida encerrada.
type MatchRecord struct {
	Mode          string
	Seed          int64
	TickRate      int16
	StartedAt     time.Time
	EndedAt       time.Time
	DurationTicks int32
	EndReason     string
	WinnerUserID  *int64
	ServerVersion string
	Season        int16
	Players       []MatchPlayerRecord
}

// SaveMatchTx persiste a partida, os resultados por jogador, as estatísticas agregadas
// e os rankings numa única transação com lock ordenado por user_id (docs/DATABASE.md §5).
func SaveMatchTx(ctx context.Context, db TxBeginner, rec MatchRecord) (int64, error) {
	if rec.Season < 1 {
		rec.Season = 1
	}
	var matchID int64
	err := WithTx(ctx, db, func(tx pgx.Tx) error {
		err := tx.QueryRow(ctx, `
			INSERT INTO matches (mode, seed, tick_rate, started_at, ended_at, duration_ticks, end_reason, winner_user_id, server_version)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
			RETURNING id
		`, rec.Mode, rec.Seed, rec.TickRate, rec.StartedAt, rec.EndedAt, rec.DurationTicks, rec.EndReason, rec.WinnerUserID, rec.ServerVersion).Scan(&matchID)
		if err != nil {
			return err
		}

		// Coleta user_ids únicos e ordena para adquirir locks na mesma ordem (evita deadlock)
		uidSet := make(map[int64]MatchPlayerRecord)
		var orderedUIDs []int64
		for _, p := range rec.Players {
			_, err := tx.Exec(ctx, `
				INSERT INTO match_players (match_id, slot, user_id, place, score, kills, deaths, blocks, powerups, platform, disconnected, rating_before, rating_after)
				VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
			`, matchID, p.Slot, p.UserID, p.Place, p.Score, p.Kills, p.Deaths, p.Blocks, p.PowerUps, p.Platform, p.Disconnected, p.RatingBefore, p.RatingAfter)
			if err != nil {
				return err
			}
			if p.UserID != nil {
				if _, seen := uidSet[*p.UserID]; !seen {
					uidSet[*p.UserID] = p
					orderedUIDs = append(orderedUIDs, *p.UserID)
				}
			}
		}

		sort.Slice(orderedUIDs, func(i, j int) bool { return orderedUIDs[i] < orderedUIDs[j] })
		isDraw := 0
		if rec.EndReason == "draw" {
			isDraw = 1
		}

		for _, uid := range orderedUIDs {
			p := uidSet[uid]
			isWin := 0
			if rec.WinnerUserID != nil && *rec.WinnerUserID == uid {
				isWin = 1
			}
			_, err := tx.Exec(ctx, `
				INSERT INTO player_statistics (
					user_id, matches_played, wins, draws, kills, deaths,
					blocks_destroyed, powerups_collected, best_score, total_score, play_time_ticks, updated_at
				) VALUES ($1, 1, $2, $3, $4, $5, $6, $7, $8, $8, $9, now())
				ON CONFLICT (user_id) DO UPDATE SET
					matches_played     = player_statistics.matches_played + 1,
					wins               = player_statistics.wins + EXCLUDED.wins,
					draws              = player_statistics.draws + EXCLUDED.draws,
					kills              = player_statistics.kills + EXCLUDED.kills,
					deaths             = player_statistics.deaths + EXCLUDED.deaths,
					blocks_destroyed   = player_statistics.blocks_destroyed + EXCLUDED.blocks_destroyed,
					powerups_collected = player_statistics.powerups_collected + EXCLUDED.powerups_collected,
					best_score         = GREATEST(player_statistics.best_score, EXCLUDED.best_score),
					total_score        = player_statistics.total_score + EXCLUDED.total_score,
					play_time_ticks    = player_statistics.play_time_ticks + EXCLUDED.play_time_ticks,
					updated_at         = now()
			`, uid, isWin, isDraw, p.Kills, p.Deaths, p.Blocks, p.PowerUps, p.Score, rec.DurationTicks)
			if err != nil {
				return err
			}

			if rec.Mode != "practice" && p.RatingAfter != nil {
				_, err := tx.Exec(ctx, `
					INSERT INTO rankings (season, mode, user_id, rating, matches, wins, updated_at)
					VALUES ($1, $2, $3, $4, 1, $5, now())
					ON CONFLICT (season, mode, user_id) DO UPDATE SET
						rating     = EXCLUDED.rating,
						matches    = rankings.matches + 1,
						wins       = rankings.wins + EXCLUDED.wins,
						updated_at = now()
				`, rec.Season, rec.Mode, uid, *p.RatingAfter, isWin)
				if err != nil {
					return err
				}
			}
		}
		return nil
	})
	return matchID, err
}
