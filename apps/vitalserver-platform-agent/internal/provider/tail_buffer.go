package provider

import "sync"

type TailBuffer struct {
	mu       sync.Mutex
	capacity int
	data     []byte
}

func NewTailBuffer(capacity int) *TailBuffer {
	return &TailBuffer{capacity: capacity}
}

func (buffer *TailBuffer) Write(data []byte) (int, error) {
	buffer.mu.Lock()
	defer buffer.mu.Unlock()
	written := len(data)
	if buffer.capacity <= 0 {
		return written, nil
	}
	if len(data) >= buffer.capacity {
		buffer.data = append(buffer.data[:0], data[len(data)-buffer.capacity:]...)
		return written, nil
	}
	overflow := len(buffer.data) + len(data) - buffer.capacity
	if overflow > 0 {
		copy(buffer.data, buffer.data[overflow:])
		buffer.data = buffer.data[:len(buffer.data)-overflow]
	}
	buffer.data = append(buffer.data, data...)
	return written, nil
}

func (buffer *TailBuffer) String() string {
	buffer.mu.Lock()
	defer buffer.mu.Unlock()
	return string(append([]byte(nil), buffer.data...))
}
