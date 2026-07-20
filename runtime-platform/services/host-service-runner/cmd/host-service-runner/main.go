// host-service-runner is the OS-service process boundary for one explicit
// Host product command. It does not discover a command, infer a service name,
// or make Host domain decisions.
package main

import (
	"errors"
	"flag"
	"fmt"
	"os"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-service-runner/internal/hostservicerunner"
)

func main() {
	definitionPath := flag.String("service-definition", "", "required absolute Host service execution definition JSON path")
	flag.Parse()
	if *definitionPath == "" || flag.NArg() != 0 {
		fmt.Fprintln(os.Stderr, "usage: host-service-runner --service-definition <absolute-path>")
		os.Exit(2)
	}
	definition, err := hostservicerunner.ReadExecutionDefinition(*definitionPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read Host service execution definition: %v\n", err)
		os.Exit(2)
	}
	if err := hostservicerunner.RunDeclaredHostService(definition); err != nil {
		if !errors.Is(err, hostservicerunner.ErrDeclaredServiceStopped) {
			fmt.Fprintf(os.Stderr, "run declared Host service %s: %v\n", definition.ServiceName, err)
			os.Exit(1)
		}
	}
}
