//go:build windows

package stagednextupdaterprocess

import (
	"context"
	"fmt"
	"io"
	"os"
	"runtime"
	"unsafe"

	"golang.org/x/sys/windows"
)

// Windows defines this attribute as ProcThreadAttributeValue(13, false, true,
// false). x/sys v0.10.0 exposes attribute-list construction but not this
// constant.
const procThreadAttributeJobList = 0x0002000d

type inheritedOutputPipe struct {
	reader *os.File
	writer *os.File
	result chan error
}

func newInheritedOutputPipe(destination io.Writer) (*inheritedOutputPipe, error) {
	reader, writer, err := os.Pipe()
	if err != nil {
		return nil, err
	}
	if err := windows.SetHandleInformation(windows.Handle(writer.Fd()), windows.HANDLE_FLAG_INHERIT, windows.HANDLE_FLAG_INHERIT); err != nil {
		_ = reader.Close()
		_ = writer.Close()
		return nil, err
	}
	result := make(chan error, 1)
	go func() {
		_, copyError := io.Copy(destination, reader)
		closeError := reader.Close()
		if copyError != nil {
			result <- copyError
			return
		}
		result <- closeError
	}()
	return &inheritedOutputPipe{reader: reader, writer: writer, result: result}, nil
}

func (pipe *inheritedOutputPipe) closeParentWriter() {
	_ = pipe.writer.Close()
}

func (pipe *inheritedOutputPipe) wait() error {
	return <-pipe.result
}

// runConfinedProcess creates the staged updater inside a Job Object at process
// creation time. JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE makes every descendant part
// of the same owned process tree and prevents a child from escaping cancellation.
func runConfinedProcess(ctx context.Context, executable string, arguments []string, standardOutput io.Writer, standardError io.Writer) error {
	if err := ctx.Err(); err != nil {
		return err
	}

	job, err := windows.CreateJobObject(nil, nil)
	if err != nil {
		return fmt.Errorf("create staged updater job object: %w", err)
	}
	jobOpen := true
	closeJob := func() {
		if jobOpen {
			_ = windows.CloseHandle(job)
			jobOpen = false
		}
	}
	defer closeJob()

	limits := windows.JOBOBJECT_EXTENDED_LIMIT_INFORMATION{}
	limits.BasicLimitInformation.LimitFlags = windows.JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
	if _, err := windows.SetInformationJobObject(job, windows.JobObjectExtendedLimitInformation, uintptr(unsafe.Pointer(&limits)), uint32(unsafe.Sizeof(limits))); err != nil {
		return fmt.Errorf("configure staged updater job object: %w", err)
	}

	standardOutputPipe, err := newInheritedOutputPipe(standardOutput)
	if err != nil {
		return fmt.Errorf("create staged updater stdout pipe: %w", err)
	}
	defer standardOutputPipe.closeParentWriter()
	standardErrorPipe, err := newInheritedOutputPipe(standardError)
	if err != nil {
		standardOutputPipe.closeParentWriter()
		_ = standardOutputPipe.wait()
		return fmt.Errorf("create staged updater stderr pipe: %w", err)
	}
	defer standardErrorPipe.closeParentWriter()

	nullInput, err := os.Open(os.DevNull)
	if err != nil {
		standardOutputPipe.closeParentWriter()
		standardErrorPipe.closeParentWriter()
		_ = standardOutputPipe.wait()
		_ = standardErrorPipe.wait()
		return fmt.Errorf("open staged updater stdin: %w", err)
	}
	defer nullInput.Close()
	if err := windows.SetHandleInformation(windows.Handle(nullInput.Fd()), windows.HANDLE_FLAG_INHERIT, windows.HANDLE_FLAG_INHERIT); err != nil {
		standardOutputPipe.closeParentWriter()
		standardErrorPipe.closeParentWriter()
		_ = standardOutputPipe.wait()
		_ = standardErrorPipe.wait()
		return fmt.Errorf("make staged updater stdin inheritable: %w", err)
	}

	attributeList, err := windows.NewProcThreadAttributeList(2)
	if err != nil {
		return fmt.Errorf("create staged updater process attributes: %w", err)
	}
	defer attributeList.Delete()
	jobHandles := []windows.Handle{job}
	if err := attributeList.Update(procThreadAttributeJobList, unsafe.Pointer(&jobHandles[0]), unsafe.Sizeof(jobHandles[0])); err != nil {
		return fmt.Errorf("bind staged updater job object at process creation: %w", err)
	}
	inheritedHandles := []windows.Handle{
		windows.Handle(nullInput.Fd()),
		windows.Handle(standardOutputPipe.writer.Fd()),
		windows.Handle(standardErrorPipe.writer.Fd()),
	}
	if err := attributeList.Update(windows.PROC_THREAD_ATTRIBUTE_HANDLE_LIST, unsafe.Pointer(&inheritedHandles[0]), uintptr(len(inheritedHandles))*unsafe.Sizeof(inheritedHandles[0])); err != nil {
		return fmt.Errorf("bind staged updater standard handles: %w", err)
	}

	executableUTF16, err := windows.UTF16PtrFromString(executable)
	if err != nil {
		return fmt.Errorf("encode staged updater executable path: %w", err)
	}
	commandLineValues := append([]string{executable}, arguments...)
	commandLineUTF16, err := windows.UTF16PtrFromString(windows.ComposeCommandLine(commandLineValues))
	if err != nil {
		return fmt.Errorf("encode staged updater command line: %w", err)
	}
	startupInfo := windows.StartupInfoEx{
		StartupInfo: windows.StartupInfo{
			Cb:        uint32(unsafe.Sizeof(windows.StartupInfoEx{})),
			Flags:     windows.STARTF_USESTDHANDLES,
			StdInput:  inheritedHandles[0],
			StdOutput: inheritedHandles[1],
			StdErr:    inheritedHandles[2],
		},
		ProcThreadAttributeList: attributeList.List(),
	}
	processInformation := windows.ProcessInformation{}
	creationFlags := uint32(windows.CREATE_DEFAULT_ERROR_MODE | windows.CREATE_UNICODE_ENVIRONMENT | windows.EXTENDED_STARTUPINFO_PRESENT)
	if err := windows.CreateProcess(executableUTF16, commandLineUTF16, nil, nil, true, creationFlags, nil, nil, &startupInfo.StartupInfo, &processInformation); err != nil {
		standardOutputPipe.closeParentWriter()
		standardErrorPipe.closeParentWriter()
		_ = standardOutputPipe.wait()
		_ = standardErrorPipe.wait()
		return fmt.Errorf("create staged updater process: %w", err)
	}
	runtime.KeepAlive(jobHandles)
	runtime.KeepAlive(inheritedHandles)
	_ = windows.CloseHandle(processInformation.Thread)
	standardOutputPipe.closeParentWriter()
	standardErrorPipe.closeParentWriter()

	waitResult := make(chan error, 1)
	go func() {
		waitResult <- waitForWindowsProcess(processInformation.Process)
	}()

	var processError error
	select {
	case processError = <-waitResult:
		closeJob()
	case <-ctx.Done():
		terminationError := windows.TerminateJobObject(job, 1)
		closeJob()
		<-waitResult
		_ = windows.CloseHandle(processInformation.Process)
		_ = standardOutputPipe.wait()
		_ = standardErrorPipe.wait()
		if terminationError != nil {
			return fmt.Errorf("terminate staged updater job object: %w", terminationError)
		}
		return ctx.Err()
	}
	_ = windows.CloseHandle(processInformation.Process)
	outputError := standardOutputPipe.wait()
	errorOutputError := standardErrorPipe.wait()
	if processError != nil {
		return processError
	}
	if outputError != nil {
		return fmt.Errorf("read staged updater stdout: %w", outputError)
	}
	if errorOutputError != nil {
		return fmt.Errorf("read staged updater stderr: %w", errorOutputError)
	}
	return nil
}

func waitForWindowsProcess(process windows.Handle) error {
	waitResult, err := windows.WaitForSingleObject(process, windows.INFINITE)
	if err != nil {
		return err
	}
	if waitResult != windows.WAIT_OBJECT_0 {
		return fmt.Errorf("unexpected staged updater wait result %d", waitResult)
	}
	var exitCode uint32
	if err := windows.GetExitCodeProcess(process, &exitCode); err != nil {
		return err
	}
	if exitCode != 0 {
		return fmt.Errorf("exit status %d", exitCode)
	}
	return nil
}
