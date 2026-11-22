package greeting

import (
	"strings"
	"testing"
)

func TestGreet(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want string
	}{
		{name: "a name", in: "world", want: "Hello, world!"},
		{name: "empty", in: "", want: "Hello, !"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := Greet(tt.in); got != tt.want {
				t.Errorf("Greet(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}

// FuzzGreet runs its seeds under plain go test; go test -fuzz=FuzzGreet explores further.
func FuzzGreet(f *testing.F) {
	f.Add("world")
	f.Add("")
	f.Fuzz(func(t *testing.T, name string) {
		if got := Greet(name); !strings.Contains(got, name) {
			t.Errorf("Greet(%q) = %q, want it to contain the name", name, got)
		}
	})
}
