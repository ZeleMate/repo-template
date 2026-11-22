package main

import (
	"bytes"
	"errors"
	"runtime/debug"
	"testing"
)

func TestRun(t *testing.T) {
	tests := []struct {
		name     string
		args     []string
		wantCode int
		wantOut  string
	}{
		{name: "greets", args: nil, wantCode: 0, wantOut: "Hello, world!\n"},
		{name: "prints the version", args: []string{"--version"}, wantCode: 0, wantOut: "dev\n"},
		{name: "rejects an unknown flag", args: []string{"--nope"}, wantCode: 2, wantOut: ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			if code := run(tt.args, &stdout, &stderr); code != tt.wantCode {
				t.Errorf("run(%q) = %d, want %d (stderr: %q)", tt.args, code, tt.wantCode, stderr.String())
			}
			if got := stdout.String(); got != tt.wantOut {
				t.Errorf("run(%q) wrote %q, want %q", tt.args, got, tt.wantOut)
			}
		})
	}
}

// failingWriter fails every write, like a closed stdout.
type failingWriter struct{}

func (failingWriter) Write([]byte) (int, error) { return 0, errors.New("write failed") }

func TestRunReportsAWriteError(t *testing.T) {
	var stderr bytes.Buffer
	if code := run(nil, failingWriter{}, &stderr); code != 1 {
		t.Errorf("run with a failing stdout = %d, want 1", code)
	}
}

func TestVersionOf(t *testing.T) {
	installed := &debug.BuildInfo{Main: debug.Module{Version: "v1.2.0"}}
	tests := []struct {
		name    string
		stamped string
		info    *debug.BuildInfo
		ok      bool
		want    string
	}{
		{name: "a stamped release build", stamped: "v1.3.0", info: installed, ok: true, want: "v1.3.0"},
		{name: "go install", stamped: "dev", info: installed, ok: true, want: "v1.2.0"},
		{name: "a local build", stamped: "dev", info: &debug.BuildInfo{Main: debug.Module{Version: "(devel)"}}, ok: true, want: "dev"},
		{name: "no build info", stamped: "dev", info: nil, ok: false, want: "dev"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := versionOf(tt.stamped, tt.info, tt.ok); got != tt.want {
				t.Errorf("versionOf(%q, …) = %q, want %q", tt.stamped, got, tt.want)
			}
		})
	}
}
