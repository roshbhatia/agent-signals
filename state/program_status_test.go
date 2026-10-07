package agentstate

import (
	"encoding/base64"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestProgramStatusStates(t *testing.T) {
	for _, status := range []string{"idle", "working", "done", "blocked", "error", "waiting"} {
		want := status
		if status == "waiting" {
			want = "blocked"
		}
		got := programStatus(state{Agent: "claude", Status: status, Reason: "your move"})
		expected := "\x1b]7501;state=" + want + ":app=claude:msg=eW91ciBtb3Zl\x1b\\"
		if got != expected {
			t.Errorf("%s: got %q, want %q", status, got, expected)
		}
	}
	for _, status := range []string{"", "unknown", "exit", "working:state=done"} {
		if got := programStatus(state{Status: status}); got != "" {
			t.Errorf("unsupported status %q emitted %q", status, got)
		}
	}
	if got := programStatus(state{Status: "clear", Agent: "claude", Reason: "ignored"}); got != "\x1b]7501;state=clear\x1b\\" {
		t.Fatalf("clear: %q", got)
	}
}

func TestProgramStatusRejectsInjectedAppAndSanitizesText(t *testing.T) {
	for _, app := range []string{"", "claude:state=done", "a;b", "é", strings.Repeat("x", 33)} {
		got := programStatus(state{Agent: app, Status: "working", Reason: "a\x00\x1b\u0085b\xff"})
		if strings.Contains(got, ":app=") {
			t.Fatalf("invalid app was emitted: %q", got)
		}
		encoded := strings.TrimSuffix(strings.Split(got, ":msg=")[1], "\x1b\\")
		decoded, err := base64.StdEncoding.DecodeString(encoded)
		if err != nil || !utf8.Valid(decoded) || string(decoded) != "a b" {
			t.Fatalf("unsafe message %q (%v)", decoded, err)
		}
	}
	got := programStatus(state{Agent: "agent-1.2_test+cli", Status: "working", Reason: strings.Repeat("界", 3000)})
	if len(got) > 4096 || !strings.Contains(got, ":app=agent-1.2_test+cli:") {
		t.Fatalf("invalid bounded report: %d bytes", len(got))
	}
}

func TestProgramStatusWithoutWezTermDoesNotWritePaneFiles(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_STATE_HOME", dir)
	t.Setenv("WEZTERM_PANE", "")
	var reports []string
	original := emitProgramStatus
	emitProgramStatus = func(value string) { reports = append(reports, value) }
	t.Cleanup(func() { emitProgramStatus = original })
	if code := Run([]string{"codex", "working", "submit"}); code != 0 {
		t.Fatalf("Run returned %d", code)
	}
	if len(reports) != 1 || !strings.Contains(reports[0], "state=working:app=codex:") {
		t.Fatalf("portable reports: %q", reports)
	}
	if _, err := os.Stat(filepath.Join(dir, "agents", "panes")); !os.IsNotExist(err) {
		t.Fatalf("created pane files without a pane identity: %v", err)
	}
	Run([]string{"codex", "done"})
	Run([]string{"codex", "exit"})
	if len(reports) != 2 || !strings.Contains(reports[1], "state=done:") {
		t.Fatalf("exit changed the completion record: %q", reports)
	}
	Run([]string{"codex", "clear"})
	if reports[2] != "\x1b]7501;state=clear\x1b\\" {
		t.Fatalf("explicit clear: %q", reports)
	}
}

func TestProgramStatusAndLegacyUserVarAreBothEmitted(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	t.Setenv("WEZTERM_PANE", "42")
	var report, legacy string
	oldProgram, oldLegacy := emitProgramStatus, emitUserVar
	emitProgramStatus = func(value string) { report = value }
	emitUserVar = func(value string) { legacy = value }
	t.Cleanup(func() { emitProgramStatus, emitUserVar = oldProgram, oldLegacy })
	Run([]string{"claude", "waiting", "approval"})
	decoded, err := base64.StdEncoding.DecodeString(legacy)
	if err != nil || !strings.HasPrefix(string(decoded), "waiting|approval|") {
		t.Fatalf("legacy transport changed: %q (%v)", decoded, err)
	}
	if !strings.Contains(report, "state=blocked:app=claude:") {
		t.Fatalf("missing OSC 7501 report: %q", report)
	}
}
