// Package rules implementa as regras determinísticas da partida em Go
// (GDD §3–8, ARCHITECTURE D-11/D-12/D-14), idênticas às do cliente GDScript
// (client/scripts/rules/) e verificadas pelos cenários em tests/scenarios/.
package rules

// PRNG implementa o gerador xorshift32 determinístico (ARCHITECTURE D-12 e §5).
type PRNG struct {
	State uint32
}

// NewPRNG cria um xorshift32 inicializado com seed (seed 0 vira 1).
func NewPRNG(seed uint32) *PRNG {
	if seed == 0 {
		seed = 1
	}
	return &PRNG{State: seed}
}

// NextU32 avança o estado e retorna o próximo uint32.
func (r *PRNG) NextU32() uint32 {
	x := r.State
	x ^= x << 13
	x ^= x >> 17
	x ^= x << 5
	r.State = x
	return x
}

// NextBound retorna um inteiro em [0, bound).
func (r *PRNG) NextBound(bound uint32) uint32 {
	if bound == 0 {
		return 0
	}
	return r.NextU32() % bound
}
