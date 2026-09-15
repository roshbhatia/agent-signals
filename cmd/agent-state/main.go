package main

import (
	"github.com/roshbhatia/agent-signals/state"
	"os"
)

func main() { os.Exit(agentstate.Run(os.Args[1:])) }
