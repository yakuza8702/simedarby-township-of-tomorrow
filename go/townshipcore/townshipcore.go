// Package townshipcore is the Go native core of the Township of Tomorrow app,
// compiled to Android via gomobile bind. It hosts the heaviest pure-compute
// jobs so the Dart layer stays UI-only:
//
//   - KnnSearch:   cosine-similarity search over packed float32 embeddings
//                  (on-device kNN classifier that closes the COCO blind spots:
//                  can / battery / cardboard / tissue have no COCO class).
//   - PHash:       64-bit DCT perceptual hash of a JPEG/PNG (no external deps).
//   - Hamming:     hamming distance between two 64-bit hex pHashes.
//   - VerifyAction: anti-exploit gate for collection actions (placeholder
//                  verification — see NOTE below).
//
// Wire format note: gomobile bind does not support []float32, so embeddings
// cross the bridge as []byte holding little-endian float32 values.
package townshipcore

import (
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"image"
	"image/jpeg"
	_ "image/png"
	"math"
	"os"
	"strings"
)

// Version reports the native core version.
func Version() string { return "0.2.1" }

// leFloat32 reads a little-endian float32 slice from bytes.
func leFloat32(b []byte) ([]float32, error) {
	if len(b)%4 != 0 {
		return nil, fmt.Errorf("float32 byte slice length %d is not a multiple of 4", len(b))
	}
	out := make([]float32, len(b)/4)
	for i := range out {
		out[i] = math.Float32frombits(binary.LittleEndian.Uint32(b[i*4:]))
	}
	return out, nil
}

// Match is one kNN hit.
type Match struct {
	Label string  `json:"label"`
	Score float64 `json:"score"` // cosine similarity in [-1, 1]
}

// KnnSearch returns the k nearest labels for a query embedding.
//
//	vec         : query embedding, little-endian float32 bytes (length dim*4)
//	db          : reference embeddings, row-major float32 bytes (rows*dim*4)
//	labelsLines : one label per reference row, "\n"-joined (gomobile bind does
//	              not support []string parameters)
//	k           : how many neighbours to return
//
// Matches are returned sorted by descending cosine similarity.
func KnnSearch(vec []byte, db []byte, labelsLines string, k int) (string, error) {
	labels := strings.Split(labelsLines, "\n")
	q, err := leFloat32(vec)
	if err != nil {
		return "", fmt.Errorf("query: %w", err)
	}
	rows, err := leFloat32(db)
	if err != nil {
		return "", fmt.Errorf("db: %w", err)
	}
	if len(labels) == 0 || len(rows) != len(labels)*len(q) {
		return "", fmt.Errorf("db rows %d * dim %d != %d floats, labels %d", len(labels), len(q), len(rows), len(labels))
	}
	dim := len(q)
	qn := make([]float64, dim)
	var qNorm float64
	for i, v := range q {
		qn[i] = float64(v)
		qNorm += qn[i] * qn[i]
	}
	qNorm = math.Sqrt(qNorm)
	if qNorm == 0 {
		return "", fmt.Errorf("query embedding is all zeros")
	}

	matches := make([]Match, 0, len(labels))
	for r := 0; r < len(labels); r++ {
		row := rows[r*dim : (r+1)*dim]
		var dot, rNorm float64
		for i := 0; i < dim; i++ {
			rv := float64(row[i])
			dot += qn[i] * rv
			rNorm += rv * rv
		}
		rNorm = math.Sqrt(rNorm)
		score := 0.0
		if rNorm > 0 {
			score = dot / (qNorm * rNorm)
		}
		matches = append(matches, Match{Label: labels[r], Score: score})
	}
	// insertion sort descending — tiny sets, no need for sort.Slice allocation churn
	for i := 1; i < len(matches); i++ {
		for j := i; j > 0 && matches[j].Score > matches[j-1].Score; j-- {
			matches[j], matches[j-1] = matches[j-1], matches[j]
		}
	}
	if k <= 0 || k > len(matches) {
		k = len(matches)
	}
	matches = matches[:k]
	out, err := json.Marshal(matches)
	if err != nil {
		return "", err
	}
	return string(out), nil
}

// PHash computes a 64-bit DCT perceptual hash of an image file and returns
// it as 16 lowercase hex characters. Works on JPEG and PNG from bytes or a
// file path (pass exactly one).
func PHash(img []byte, path string) (string, error) {
	var m image.Image
	if len(img) > 0 {
		decoded, _, err := image.Decode(strings.NewReader(string(img)))
		if err != nil {
			return "", fmt.Errorf("decode image: %w", err)
		}
		m = decoded
	} else if path != "" {
		f, err := os.Open(path)
		if err != nil {
			return "", err
		}
		defer f.Close()
		decoded, _, err := image.Decode(f)
		if err != nil {
			return "", fmt.Errorf("decode %s: %w", path, err)
		}
		m = decoded
	} else {
		return "", fmt.Errorf("pHash: provide image bytes or a path")
	}
	b := m.Bounds()
	w, h := b.Dx(), b.Dy()
	if w == 0 || h == 0 {
		return "", fmt.Errorf("pHash: empty image")
	}
	// 32x32 grayscale box average
	const S = 32
	g := make([]float64, S*S)
	for y := 0; y < S; y++ {
		sy0, sy1 := b.Min.Y+y*h/S, b.Min.Y+(y+1)*h/S
		for x := 0; x < S; x++ {
			sx0, sx1 := b.Min.X+x*w/S, b.Min.X+(x+1)*w/S
			var sum float64
			var n int
			for sy := sy0; sy < sy1; sy++ {
				for sx := sx0; sx < sx1; sx++ {
					r, gr, bl, _ := m.At(sx, sy).RGBA()
					sum += 0.299*float64(r>>8) + 0.587*float64(gr>>8) + 0.114*float64(bl>>8)
					n++
				}
			}
			if n > 0 {
				g[y*S+x] = sum / float64(n)
			}
		}
	}
	// 2D DCT (rows then cols), keep 8x8 low-frequency block, drop DC
	dctRow := make([]float64, S*S)
	for u := 0; u < 8; u++ {
		for x := 0; x < S; x++ {
			var s float64
			for i := 0; i < S; i++ {
				s += g[u*S+i] * math.Cos((2*float64(i)+1)*float64(x)*math.Pi/(2*float64(S)))
			}
			dctRow[u*S+x] = s
		}
	}
	coeffs := make([]float64, 64)
	for v := 0; v < 8; v++ {
		for y := 0; y < 8; y++ { // 8x8 low-frequency block: coeffs[v*8+y] must stay < 64
			var s float64
			for i := 0; i < S; i++ {
				s += dctRow[v*S+i] * math.Cos((2*float64(i)+1)*float64(y)*math.Pi/(2*float64(S)))
			}
			coeffs[v*8+y] = s
		}
	}
	// median over the 63 non-DC coefficients
	med := make([]float64, 63)
	copy(med, coeffs[1:])
	// small insertion sort
	for i := 1; i < len(med); i++ {
		for j := i; j > 0 && med[j] < med[j-1]; j-- {
			med[j], med[j-1] = med[j-1], med[j]
		}
	}
	mid := med[len(med)/2]
	var hash uint64
	for i := 0; i < 64; i++ {
		if coeffs[i] > mid {
			hash |= 1 << i
		}
	}
	return hex.EncodeToString([]byte{byte(hash >> 56), byte(hash >> 48), byte(hash >> 40), byte(hash >> 32),
		byte(hash >> 24), byte(hash >> 16), byte(hash >> 8), byte(hash)}), nil
}

// Hamming distance between two 16-hex-char 64-bit pHashes.
func Hamming(a, b string) (int, error) {
	if len(a) != 16 || len(b) != 16 {
		return 0, fmt.Errorf("pHash must be 16 hex chars, got %d and %d", len(a), len(b))
	}
	ab, err := hex.DecodeString(a)
	if err != nil {
		return 0, err
	}
	bb, err := hex.DecodeString(b)
	if err != nil {
		return 0, err
	}
	var d int
	for i := 0; i < 8; i++ {
		x := ab[i] ^ bb[i]
		for x != 0 {
			d += int(x & 1)
			x >>= 1
		}
	}
	return d, nil
}

// ============================================================================
// VerifyAction — anti-exploit gate for collection actions (PLACEHOLDER).
//
// The real anti-exploit design (backend task) is: server-side verification of
// the disposal event — geotag near a registered bin/bay, weight station entry,
// or a household QR handshake — with the photo hash chained to the task. Until
// that backend exists, this native stub enforces the client-side checks that
// are already meaningful, and labels the result PLACEHOLDER so nobody mistakes
// it for real verification:
//
//   - the action must be recycle | remove | dispose (anything else rejected);
//   - the proof photo must exist and hash against itself (not corrupted);
//   - the proof photo must NOT be a re-used capture of the one that created the
//     collection entry (hamming distance >= 12 of 64 bits) — stops the cheapest
//     exploit: spam the same photo.
// ============================================================================

// VerifyReport is the JSON VerifyAction returns.
type VerifyReport struct {
	Status   string `json:"status"` // ACCEPT_PLACEHOLDER | REJECT_*
	Action   string `json:"action"`
	Points   int    `json:"points"` // placeholder economy: 1 point per accepted action
	Distance int    `json:"distance"`
	Reason   string `json:"reason"`
	Engine   string `json:"engine"`
}

// VerifyAction validates a collection action against its proof photo.
//
//	entryHashHex : pHash (16 hex chars) of the photo that CREATED the entry
//	proofPhoto   : JPEG/PNG bytes of the photo proving the completed task
func VerifyAction(action string, entryHashHex string, proofPhoto []byte) (string, error) {
	rep := VerifyReport{Action: action, Engine: "townshipcore-go " + Version() + " (placeholder verification)"}
	if action != "recycle" && action != "remove" && action != "dispose" {
		rep.Status, rep.Reason = "REJECT_BAD_ACTION", fmt.Sprintf("unknown action %q", action)
		return marshal(rep), nil
	}
	proof, err := PHash(proofPhoto, "")
	if err != nil {
		return "", fmt.Errorf("proof photo: %w", err)
	}
	if len(entryHashHex) == 16 {
		d, err := Hamming(entryHashHex, proof)
		if err != nil {
			return "", err
		}
		rep.Distance = d
		if d < 12 {
			rep.Status, rep.Reason = "REJECT_DUPLICATE_PROOF",
				"proof photo is a re-used capture of the entry photo (pHash distance "+fmt.Sprint(d)+")"
			return marshal(rep), nil
		}
	}
	rep.Status, rep.Points, rep.Reason = "ACCEPT_PLACEHOLDER", 1,
		"client-side placeholder checks passed; real verification lands with the backend"
	return marshal(rep), nil
}

func marshal(rep VerifyReport) string {
	out, err := json.Marshal(rep)
	if err != nil {
		return `{"status":"ERROR","reason":"marshal failure"}`
	}
	return string(out)
}

var _ = jpeg.Decode // keep image/jpeg linked for JPEG proof photos
