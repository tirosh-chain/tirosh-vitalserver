import type {
  NativeVitalUploadIndexEvidence,
} from "../../../domain/native-vital-upload";

export interface NativeVitalUploadIndexPort {
  find(filename: string): Promise<NativeVitalUploadIndexEvidence | null>;
}
