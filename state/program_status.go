package agentstate

import (
	"encoding/base64"
	"fmt"
	"os"
	"strings"
)

func programStatus(record state) string {
	status := record.Status
	if status == "waiting" {
		status = "blocked"
	}
	switch status {
	case "idle", "working", "done", "blocked", "error", "clear":
	default:
		return ""
	}
	body := "state=" + status
	if status != "clear" {
		if validProgramName(record.Agent) {
			body += ":app=" + record.Agent
		}
		message := strings.Map(func(r rune) rune {
			if r < 0x20 || (r >= 0x7f && r <= 0x9f) {
				return ' '
			}
			return r
		}, strings.ToValidUTF8(record.Reason, ""))
		message = truncate(strings.Join(strings.Fields(message), " "), reasonLimit)
		if message != "" {
			body += ":msg=" + base64.StdEncoding.EncodeToString([]byte(message))
		}
	}
	return "\x1b]7501;" + body + "\x1b\\"
}

func validProgramName(name string) bool {
	if len(name) == 0 || len(name) > 32 {
		return false
	}
	for _, r := range name {
		if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') ||
			(r >= '0' && r <= '9') || strings.ContainsRune("_.+-", r)) {
			return false
		}
	}
	return true
}

var emitProgramStatus = writeProgramStatus

func writeProgramStatus(sequence string) {
	tty, err := os.OpenFile("/dev/tty", os.O_WRONLY, 0)
	if err != nil {
		return
	}
	defer func() { _ = tty.Close() }()
	_, _ = fmt.Fprint(tty, sequence)
}
