// e-session-rec records a terminal session: it runs the shell on a pty, tees output to the log and
// the screen, forwards SIGWINCH, and writes an OSC 9002 size marker so the viewer can replay at the
// recorded dimensions. Run by e-session-log as: e-session-rec <logfile> [shell].
package main

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"sync"
	"syscall"

	"github.com/creack/pty"
	"golang.org/x/term"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: e-session-rec <logfile> [shell]")
		os.Exit(2)
	}
	shell := os.Getenv("SHELL")
	if len(os.Args) > 2 && os.Args[2] != "" {
		shell = os.Args[2]
	}
	if shell == "" {
		shell = "/bin/sh"
	}

	logf, err := os.OpenFile(os.Args[1], os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		runShell(shell) // never block the user because logging failed
	}

	cmd := exec.Command(shell)
	var ptmx *os.File
	if ws, e := pty.GetsizeFull(os.Stdin); e == nil {
		ptmx, err = pty.StartWithSize(cmd, ws)
	} else {
		ptmx, err = pty.Start(cmd)
	}
	if err != nil {
		logf.Close()
		runShell(shell)
	}

	log := &syncWriter{w: logf}
	writeSize := func() {
		if ws, e := pty.GetsizeFull(os.Stdin); e == nil {
			fmt.Fprintf(log, "\x1b]9002;size;%d;%d\x07", ws.Rows, ws.Cols)
		}
	}
	writeSize()

	winch := make(chan os.Signal, 1)
	signal.Notify(winch, syscall.SIGWINCH)
	go func() {
		for range winch {
			_ = pty.InheritSize(os.Stdin, ptmx)
			_ = cmd.Process.Signal(syscall.SIGWINCH)
			writeSize()
		}
	}()

	var saved *term.State
	if s, e := term.MakeRaw(int(os.Stdin.Fd())); e == nil {
		saved = s
	}
	var once sync.Once
	restore := func() {
		once.Do(func() {
			if saved != nil {
				_ = term.Restore(int(os.Stdin.Fd()), saved)
			}
		})
	}
	defer restore() // also covers a panic, since deferred calls run while unwinding

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGHUP)
	go func() { <-stop; restore(); os.Exit(1) }() // never leave the terminal raw if killed

	go func() { _, _ = io.Copy(ptmx, os.Stdin) }()
	buf := make([]byte, 65536)
	for {
		n, e := ptmx.Read(buf)
		if n > 0 {
			_, _ = os.Stdout.Write(buf[:n])
			_, _ = log.Write(buf[:n])
		}
		if e != nil {
			break
		}
	}

	restore()
	os.Exit(exitCode(cmd.Wait()))
}

type syncWriter struct {
	mu sync.Mutex
	w  io.Writer
}

func (s *syncWriter) Write(b []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.w.Write(b)
}

func runShell(shell string) {
	_ = syscall.Exec(shell, []string{shell}, os.Environ())
	os.Exit(127)
}

func exitCode(err error) int {
	if err == nil {
		return 0
	}
	if ee, ok := err.(*exec.ExitError); ok {
		return ee.ExitCode()
	}
	return 1
}
