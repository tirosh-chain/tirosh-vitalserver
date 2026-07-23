import type {
  NativeVitalUploadRecord,
} from "../../../domain/native-vital-upload";

export interface NativeVitalUploadRegistryPort {
  get(uploadId: string): NativeVitalUploadRecord | null;
  list(): NativeVitalUploadRecord[];
  save(record: NativeVitalUploadRecord): void;
}
