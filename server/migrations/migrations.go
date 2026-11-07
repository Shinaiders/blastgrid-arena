// Package migrations embute os arquivos SQL versionados no binário
// (NNNN_nome.up.sql / NNNN_nome.down.sql). O runner fica em internal/persistence.
package migrations

import "embed"

// FS contém todas as migrations do diretório.
//
//go:embed *.sql
var FS embed.FS
