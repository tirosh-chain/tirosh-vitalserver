package provider

import "testing"

func TestTailBufferRetainsBoundedFailureEvidence(t *testing.T) {
	buffer := NewTailBuffer(8)
	if count, err := buffer.Write([]byte("12345")); err != nil || count != 5 {
		t.Fatalf("first write count=%d error=%v", count, err)
	}
	if count, err := buffer.Write([]byte("67890")); err != nil || count != 5 {
		t.Fatalf("second write count=%d error=%v", count, err)
	}
	if actual := buffer.String(); actual != "34567890" {
		t.Fatalf("tail=%q", actual)
	}
	if _, err := buffer.Write([]byte("abcdefghijk")); err != nil {
		t.Fatal(err)
	}
	if actual := buffer.String(); actual != "defghijk" {
		t.Fatalf("oversized tail=%q", actual)
	}
}
